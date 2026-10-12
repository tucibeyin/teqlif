#!/usr/bin/env python3
"""LiveKit room subscriber — ses/görüntüyü MKV dosyasına kaydeder.

LiveKit WebSocket signaling protokolü (protocol=15) üzerinden odaya
hidden subscriber olarak bağlanır; aiortc ile WebRTC track'lerini alır
ve PyAV (MediaRecorder) ile lokal MKV dosyasına yazar.

Bant genişliği: bağlantı 127.0.0.1 üzerinden kurulur — dış trafik yok.

Kullanım:
  python livekit_subscriber.py \\
      --room      <room_name> \\
      --ws-url    ws://127.0.0.1:7880 \\
      --api-key   <key> \\
      --api-secret <secret> \\
      --output    /var/recordings/raw/123_20261012.mkv

Çıkış kodları:
  0 → kayıt tamamlandı (yayıncı ayrıldı)
  1 → bağlantı / signaling hatası
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import logging
import signal
import sys
import time
from pathlib import Path

import aiohttp
from aiortc import RTCIceCandidate, RTCPeerConnection, RTCSessionDescription
from aiortc.contrib.media import MediaRecorder
from livekit.protocol import rtc as lk_rtc
from livekit.protocol import models as lk_models

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [livekit-subscriber] %(levelname)s %(message)s",
)
logger = logging.getLogger("livekit-subscriber")

_MAX_DURATION_S = 7200  # 2 saat güvenlik sınırı


# ── JWT ───────────────────────────────────────────────────────────────────────

def _make_token(room: str, api_key: str, api_secret: str) -> str:
    def b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    now = int(time.time())
    header  = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({
        "iss": api_key,
        "sub": f"rec-{room[:12]}",
        "iat": now,
        "exp": now + 86400,
        "video": {
            "room":         room,
            "roomJoin":     True,
            "hidden":       True,
            "recorder":     True,
            "canSubscribe": True,
        },
    }, separators=(",", ":")).encode())

    signing = f"{header}.{payload}"
    sig     = b64url(hmac.new(api_secret.encode(), signing.encode(), hashlib.sha256).digest())
    return f"{signing}.{sig}"


# ── ICE candidate parse ───────────────────────────────────────────────────────

def _parse_ice(candidate_init: str) -> RTCIceCandidate | None:
    try:
        data = json.loads(candidate_init)
        raw  = data.get("candidate", "")
        if not raw or raw == "":
            return None
        # "candidate:foundation component protocol priority ip port typ type ..."
        parts = raw.split()
        if len(parts) < 8:
            return None
        return RTCIceCandidate(
            component    = int(parts[1]),
            foundation   = parts[0].split(":", 1)[1] if ":" in parts[0] else parts[0],
            ip           = parts[4],
            port         = int(parts[5]),
            priority     = int(parts[3]),
            protocol     = parts[2].lower(),
            type         = parts[7],
            sdpMid        = data.get("sdpMid"),
            sdpMLineIndex = data.get("sdpMLineIndex"),
        )
    except Exception as exc:
        logger.debug("ICE parse atlandı: %s", exc)
        return None


# ── Signaling loop ────────────────────────────────────────────────────────────

async def _run(room: str, ws_url: str, api_key: str, api_secret: str, output: Path) -> None:
    token = _make_token(room, api_key, api_secret)
    url   = (
        f"{ws_url}/rtc"
        f"?access_token={token}"
        f"&protocol=7"
        f"&auto_subscribe=0"
        f"&sdk=py&version=0.1.0"
    )

    recorder         = MediaRecorder(str(output))
    pc               = RTCPeerConnection()
    stop_evt         = asyncio.Event()
    pending_ice: list[RTCIceCandidate] = []
    recording_started = False
    subscribed_sids: set[str] = set()  # subscribe edilmiş track SID'leri

    # ── PC ICE → server ───────────────────────────────────────────────────────
    async def _send_ice(ws: aiohttp.ClientWebSocketResponse, cand: RTCIceCandidate) -> None:
        if cand is None:
            return
        req             = lk_rtc.SignalRequest()
        req.trickle.candidateInit = json.dumps({
            "candidate": (
                f"candidate:{cand.foundation} {cand.component} "
                f"{cand.protocol.upper()} {cand.priority} "
                f"{cand.ip} {cand.port} typ {cand.type}"
            ),
            "sdpMid":        cand.sdpMid or "0",
            "sdpMLineIndex": cand.sdpMLineIndex or 0,
        })
        req.trickle.target = lk_rtc.SignalTarget.Value("SUBSCRIBER")
        await ws.send_bytes(req.SerializeToString())

    # ── Tracks → recorder ────────────────────────────────────────────────────
    @pc.on("track")
    def on_track(track) -> None:
        recorder.addTrack(track)
        logger.info("Track alındı: %s", track.kind)

    # ── Timeout guard ─────────────────────────────────────────────────────────
    async def _timeout_guard() -> None:
        await asyncio.sleep(_MAX_DURATION_S)
        logger.warning("Maksimum kayıt süresi aşıldı (%ds), durduruluyor", _MAX_DURATION_S)
        stop_evt.set()

    asyncio.create_task(_timeout_guard())

    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(
            url,
            heartbeat=20,
            max_msg_size=4 * 1024 * 1024,
        ) as ws:
            logger.info("LiveKit sinyal bağlantısı kuruldu | room=%s ws=%s", room, ws_url)

            # ICE gönderici closure
            @pc.on("icecandidate")
            def on_ice(cand) -> None:
                if cand:
                    asyncio.ensure_future(_send_ice(ws, cand))

            async for msg in ws:
                if stop_evt.is_set():
                    break
                if msg.type != aiohttp.WSMsgType.BINARY:
                    if msg.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR):
                        logger.info("WS bağlantısı kapandı: %s", msg.type)
                        break
                    continue

                resp = lk_rtc.SignalResponse()
                resp.ParseFromString(msg.data)
                kind = resp.WhichOneof("message")

                if kind == "join":
                    join = resp.join
                    logger.info(
                        "Odaya katıldı | server=%s katılımcılar=%d",
                        join.server_version,
                        len(join.other_participants),
                    )
                    # auto_subscribe=0: subscription timing kontrolü.
                    # LiveKit, recorder=true token ile bağlanan subscriber'a
                    # zaten en yüksek kaliteyi forward eder; kalite kısıtlaması
                    # koymak gerekmez ve hukuki kayıt için tam kalite şarttır.
                    all_sids = [
                        t.sid
                        for p in join.other_participants
                        for t in p.tracks
                        if t.sid not in subscribed_sids
                    ]
                    if all_sids:
                        sub_req = lk_rtc.SignalRequest()
                        sub_req.subscription.track_sids.extend(all_sids)
                        sub_req.subscription.subscribe = True
                        await ws.send_bytes(sub_req.SerializeToString())
                        subscribed_sids.update(all_sids)
                        logger.info("Tracklere abone olundu | %d track", len(all_sids))

                elif kind == "offer":
                    # Sunucunun subscriber SDP offer'ı
                    sdp = resp.offer
                    await pc.setRemoteDescription(
                        RTCSessionDescription(type=sdp.type, sdp=sdp.sdp)
                    )
                    for c in pending_ice:
                        await pc.addIceCandidate(c)
                    pending_ice.clear()

                    answer = await pc.createAnswer()
                    await pc.setLocalDescription(answer)

                    req         = lk_rtc.SignalRequest()
                    req.answer.type = answer.type
                    req.answer.sdp  = answer.sdp
                    await ws.send_bytes(req.SerializeToString())

                    if not recording_started:
                        recording_started = True
                        await recorder.start()
                        logger.info("Kayıt başladı → %s", output.name)

                elif kind == "trickle":
                    trickle = resp.trickle
                    # Subscriber PC için adayları uygula
                    if trickle.target == lk_rtc.SignalTarget.Value("SUBSCRIBER"):
                        cand = _parse_ice(trickle.candidateInit)
                        if cand:
                            if pc.remoteDescription:
                                await pc.addIceCandidate(cand)
                            else:
                                pending_ice.append(cand)

                elif kind == "update":
                    new_all_sids = []
                    for p in resp.update.participants:
                        if p.state == lk_models.ParticipantInfo.State.Value("DISCONNECTED"):
                            if p.tracks:  # publisher idi
                                logger.info("Yayıncı (%s) odadan ayrıldı", p.identity)
                                stop_evt.set()
                                break
                        else:
                            for t in p.tracks:
                                if t.sid not in subscribed_sids:
                                    new_all_sids.append(t.sid)
                    if not stop_evt.is_set() and new_all_sids:
                        sub_req = lk_rtc.SignalRequest()
                        sub_req.subscription.track_sids.extend(new_all_sids)
                        sub_req.subscription.subscribe = True
                        await ws.send_bytes(sub_req.SerializeToString())
                        subscribed_sids.update(new_all_sids)
                        logger.info("Güncelleme: yeni tracklere abone olundu | %d track", len(new_all_sids))

                elif kind == "leave":
                    logger.info("Sunucu leave mesajı gönderdi")
                    stop_evt.set()

                else:
                    logger.debug("Sinyal mesajı: kind=%s", kind)

    # ── Temizlik ──────────────────────────────────────────────────────────────
    try:
        if recording_started:
            await recorder.stop()
    except Exception as exc:
        logger.warning("recorder.stop hatası: %s", exc)

    await pc.close()

    if output.exists():
        size_mb = output.stat().st_size / 1_048_576
        logger.info("Kayıt tamamlandı | %s (%.1f MB)", output.name, size_mb)
    else:
        logger.warning("Çıktı dosyası oluşturulmadı: %s", output)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="LiveKit room kaydedici")
    parser.add_argument("--room",       required=True)
    parser.add_argument("--ws-url",     required=True)
    parser.add_argument("--api-key",    required=True)
    parser.add_argument("--api-secret", required=True)
    parser.add_argument("--output",     required=True)
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    loop = asyncio.new_event_loop()

    def _on_signal(*_):
        logger.info("SIGTERM alındı, kayıt durduruluyor")
        # stop_evt'i dışarıdan set edemeyiz; loop'u durduruyoruz
        loop.stop()

    signal.signal(signal.SIGTERM, _on_signal)
    signal.signal(signal.SIGINT,  _on_signal)

    try:
        loop.run_until_complete(_run(
            room       = args.room,
            ws_url     = args.ws_url,
            api_key    = args.api_key,
            api_secret = args.api_secret,
            output     = output,
        ))
    except Exception as exc:
        logger.error("Hata: %s", exc)
        sys.exit(1)
    finally:
        loop.close()


if __name__ == "__main__":
    main()
