#!/usr/bin/env python3
"""LiveKit relay subprocess — source_node'u izler, relay_node'a yeniden yayınlar.

- source_room'a hidden subscriber (canSubscribe: true, hidden: true) olarak bağlanır.
- relay_room'a publisher (canPublish: true, identity=host_identity) olarak bağlanır.
- Host'un ses/video track'lerini decode, relay source'a push eder.
- İlk video frame relay source'a pushlandıktan sonra live:relay:ready:{room} yazar.
- 10s heartbeat ile key'i tazer (TTL=30s).
- H3: on_track_subscribed'da HIGH simulcast layer talep eder.

Kullanım:
  python livekit_relay.py \\
      --source-url   ws://10.10.0.3:7880 \\
      --target-url   ws://10.10.0.4:7880 \\
      --room         <source_room_name> \\
      --relay-room   <relay_room_name> \\
      --host-identity <str_host_id> \\
      --api-key      <key> \\
      --api-secret   <secret> \\
      --node-id      node4 \\
      --redis-url    redis://127.0.0.1:6379
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import signal
import sys
import time
from pathlib import Path

from livekit import rtc

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [livekit-relay] %(levelname)s %(message)s",
)
logger = logging.getLogger("livekit-relay")

_RELAY_READY_KEY = "live:relay:ready:{room}"
_RELAY_READY_TTL = 30  # saniye — heartbeat ile tazelenir
_HEARTBEAT_INTERVAL = 10  # saniye


# ── JWT ───────────────────────────────────────────────────────────────────────

def _make_token(
    room: str,
    api_key: str,
    api_secret: str,
    identity: str,
    can_publish: bool,
    can_subscribe: bool,
    hidden: bool = False,
) -> str:
    def b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    now = int(time.time())
    header  = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({
        "iss": api_key,
        "sub": identity,
        "iat": now,
        "exp": now + 86400,
        "video": {
            "room":          room,
            "roomJoin":      True,
            "hidden":        hidden,
            "canPublish":    can_publish,
            "canSubscribe":  can_subscribe,
            "canPublishData": False,
        },
    }, separators=(",", ":")).encode())
    signing = f"{header}.{payload}"
    sig = b64url(hmac.new(api_secret.encode(), signing.encode(), hashlib.sha256).digest())
    return f"{signing}.{sig}"


# ── Ana relay döngüsü ──────────────────────────────────────────────────────────

async def _run(
    source_url: str,
    target_url: str,
    room_name: str,
    relay_room: str,
    host_identity: str,
    api_key: str,
    api_secret: str,
    node_id: str,
    redis_url: str,
    stop_evt: asyncio.Event,
) -> None:
    ready_key = _RELAY_READY_KEY.format(room=room_name)
    ready_sent = asyncio.Event()

    # ── Relay room (publisher) bağlantısı ──────────────────────────────────────
    relay_token = _make_token(
        relay_room, api_key, api_secret,
        identity=host_identity,
        can_publish=True, can_subscribe=False,
    )
    relay_room_obj = rtc.Room()

    # Video/audio source — decode edilmiş frame'leri buraya pushluyoruz
    video_source = rtc.VideoSource()
    audio_source = rtc.AudioSource(sample_rate=48000, num_channels=2)
    local_video  = rtc.LocalVideoTrack.create_video_track("relay-video", video_source)
    local_audio  = rtc.LocalAudioTrack.create_audio_track("relay-audio", audio_source)

    relay_publish_opts = rtc.TrackPublishOptions(
        simulcast=False,  # relay tek kalite — decode/re-encode yükünü sınırla
        source=rtc.TrackSource.SOURCE_CAMERA,
    )

    @relay_room_obj.on("disconnected")
    def _relay_disconnected(reason):
        logger.warning("Relay room bağlantısı kesildi: %s", reason)
        stop_evt.set()

    logger.info("Relay room'a bağlanılıyor | %s → %s", relay_room, target_url)
    await relay_room_obj.connect(target_url, relay_token, options=rtc.RoomOptions(auto_subscribe=False))
    await relay_room_obj.local_participant.publish_track(local_video, relay_publish_opts)
    await relay_room_obj.local_participant.publish_track(local_audio)
    logger.info("Relay room bağlandı, track'ler publish edildi | room=%s", relay_room)

    # ── Source room (subscriber) bağlantısı ───────────────────────────────────
    src_identity = f"relay-{room_name[:12]}"
    source_token = _make_token(
        room_name, api_key, api_secret,
        identity=src_identity,
        can_publish=False, can_subscribe=True,
        hidden=True,
    )
    source_room_obj = rtc.Room()
    all_tasks: list[asyncio.Task] = []

    # ── Frame forward döngüleri ────────────────────────────────────────────────

    async def _forward_video(track: rtc.RemoteVideoTrack) -> None:
        vs = rtc.VideoStream(track, format=rtc.VideoBufferType.RGBA)
        frame_count = 0
        try:
            async for event in vs:
                frame = event.frame
                frame_count += 1
                video_source.capture_frame(frame)
                if frame_count == 1:
                    logger.info("İlk video frame relay odasına basıldı | room=%s", relay_room)
                    ready_sent.set()
                if stop_evt.is_set():
                    break
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.error("_forward_video hata: %s", exc)
        finally:
            await vs.aclose()

    async def _forward_audio(track: rtc.RemoteAudioTrack) -> None:
        ast = rtc.AudioStream(track)
        try:
            async for event in ast:
                audio_source.capture_frame(event.frame)
                if stop_evt.is_set():
                    break
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.error("_forward_audio hata: %s", exc)
        finally:
            await ast.aclose()

    @source_room_obj.on("track_subscribed")
    def on_track_subscribed(track, publication, participant):
        if participant.identity != host_identity:
            return  # sadece hedef katılımcının track'lerini relay'le
        logger.info(
            "Track subscribe edildi | kind=%s participant=%s",
            track.kind, participant.identity,
        )
        # H3: HIGH simulcast layer zorunlu
        if isinstance(track, rtc.RemoteVideoTrack):
            publication.set_video_quality(rtc.VideoQuality.VIDEO_QUALITY_HIGH)
            all_tasks.append(asyncio.ensure_future(_forward_video(track)))
        elif isinstance(track, rtc.RemoteAudioTrack):
            all_tasks.append(asyncio.ensure_future(_forward_audio(track)))

    @source_room_obj.on("participant_disconnected")
    def on_participant_disconnected(participant):
        if participant.identity == host_identity:
            logger.info("Host source room'dan ayrıldı — relay durduruluyor")
            stop_evt.set()

    @source_room_obj.on("disconnected")
    def on_source_disconnected(reason):
        logger.warning("Source room bağlantısı kesildi: %s", reason)
        stop_evt.set()

    logger.info("Source room'a bağlanılıyor | %s → %s", room_name, source_url)
    await source_room_obj.connect(source_url, source_token, options=rtc.RoomOptions(auto_subscribe=True))
    logger.info("Source room bağlandı | katılımcılar=%d", len(source_room_obj.remote_participants))

    # ── Redis ready key ve heartbeat ──────────────────────────────────────────

    async def _write_ready_and_heartbeat() -> None:
        """İlk frame gelene kadar bekler, sonra Redis'e yazar ve heartbeat döngüsü başlatır."""
        try:
            import redis.asyncio as _redis
            r = _redis.from_url(redis_url, decode_responses=True)

            await asyncio.wait_for(ready_sent.wait(), timeout=30)

            payload = json.dumps({
                "relay_node_id": node_id,
                "relay_url":     target_url,
                "relay_room":    relay_room,
            })
            await r.set(ready_key, payload, ex=_RELAY_READY_TTL)
            logger.info("live:relay:ready:%s yazıldı (TTL=%ds)", room_name, _RELAY_READY_TTL)

            # Heartbeat: process yaşadıkça TTL'i tazele
            while not stop_evt.is_set():
                await asyncio.sleep(_HEARTBEAT_INTERVAL)
                if stop_evt.is_set():
                    break
                await r.expire(ready_key, _RELAY_READY_TTL)

            await r.delete(ready_key)
            logger.info("live:relay:ready:%s silindi", room_name)
            await r.aclose()
        except asyncio.TimeoutError:
            logger.error("İlk video frame 30s içinde gelmedi — relay başlatma başarısız")
            stop_evt.set()
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.error("Redis heartbeat hatası: %s", exc)

    all_tasks.append(asyncio.ensure_future(_write_ready_and_heartbeat()))

    # ── Dur ───────────────────────────────────────────────────────────────────
    await stop_evt.wait()

    for task in all_tasks:
        task.cancel()
    await asyncio.gather(*all_tasks, return_exceptions=True)

    try:
        await source_room_obj.disconnect()
    except Exception:
        pass
    try:
        await relay_room_obj.disconnect()
    except Exception:
        pass

    logger.info("Relay subprocess tamamlandı | room=%s relay_room=%s", room_name, relay_room)


# ── Entry point ───────────────────────────────────────────────────────────────

async def _main_async() -> None:
    parser = argparse.ArgumentParser(description="LiveKit relay subprocess")
    parser.add_argument("--source-url",    required=True)
    parser.add_argument("--target-url",    required=True)
    parser.add_argument("--room",          required=True)
    parser.add_argument("--relay-room",    required=True)
    parser.add_argument("--host-identity", required=True)
    parser.add_argument("--api-key",       required=True)
    parser.add_argument("--api-secret",    required=True)
    parser.add_argument("--node-id",       default=os.environ.get("AGENT_NODE_ID", "unknown"))
    parser.add_argument("--redis-url",     default=os.environ.get("REDIS_URL", "redis://127.0.0.1:6379"))
    args = parser.parse_args()

    stop_evt = asyncio.Event()
    loop     = asyncio.get_running_loop()

    def _on_signal() -> None:
        logger.info("Sinyal alındı, durduruluyor")
        stop_evt.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _on_signal)

    try:
        await _run(
            source_url    = args.source_url,
            target_url    = args.target_url,
            room_name     = args.room,
            relay_room    = args.relay_room,
            host_identity = args.host_identity,
            api_key       = args.api_key,
            api_secret    = args.api_secret,
            node_id       = args.node_id,
            redis_url     = args.redis_url,
            stop_evt      = stop_evt,
        )
    except Exception as exc:
        logger.error("Relay hata: %s", exc)
        sys.exit(1)
    finally:
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.remove_signal_handler(sig)


def main() -> None:
    asyncio.run(_main_async())


if __name__ == "__main__":
    main()
