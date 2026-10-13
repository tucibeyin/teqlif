#!/usr/bin/env python3
"""LiveKit room subscriber — ses/görüntüyü MKV dosyasına kaydeder.

livekit-rtc (Rust tabanlı resmi SDK) kullanır. Her stream için
teqlif-agent tarafından subprocess olarak başlatılır.

Kullanım:
  python livekit_subscriber.py \
      --room      <room_name> \
      --ws-url    ws://127.0.0.1:7880 \
      --api-key   <key> \
      --api-secret <secret> \
      --output    /var/recordings/raw/123_20261012.mkv
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

import time

import av
from livekit import rtc

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [livekit-subscriber] %(levelname)s %(message)s",
)
logger = logging.getLogger("livekit-subscriber")

_MAX_DURATION_S    = 7200  # 2 saat güvenlik sınırı
_QUALITY_STABLE_S  = 0.5   # resolution bu kadar süre değişmezse stabilize sayılır
_QUALITY_TIMEOUT_S = 3.0   # HIGH layer bu kadar içinde gelmezse mevcut kaliteyle aç


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
    sig = b64url(hmac.new(api_secret.encode(), signing.encode(), hashlib.sha256).digest())
    return f"{signing}.{sig}"


# ── MKV writer ────────────────────────────────────────────────────────────────

class MKVWriter:
    """VP8 + Opus MKV kaydedici.

    hint_video / hint_audio ile boyut/rate bilgisi alır,
    open_container() çağrıldığında tüm stream'lerle container açar.
    """

    def __init__(self, path: Path) -> None:
        self._path    = path
        self._container: av.container.OutputContainer | None = None
        self._vstr: av.VideoStream | None = None
        self._astr: av.AudioStream | None = None
        self._afifo: av.AudioFifo | None  = None
        self._vinfo: tuple[int, int] | None = None   # (width, height)
        self._vinfo_at: float | None = None           # monotonic — son resolution değişimi
        self._ainfo: tuple[int, int] | None = None   # (sample_rate, channels)
        self._vpts = 0
        self._apts = 0

    def hint_video(self, width: int, height: int) -> None:
        if self._container is not None:
            return  # container açıkken resolution değişemez
        new_px = width * height
        cur_px = self._vinfo[0] * self._vinfo[1] if self._vinfo else 0
        if new_px >= cur_px and self._vinfo != (width, height):
            self._vinfo = (width, height)
            self._vinfo_at = time.monotonic()

    def hint_audio(self, sample_rate: int, channels: int) -> None:
        if self._ainfo is None:
            self._ainfo = (sample_rate, channels)

    @property
    def has_video_hint(self) -> bool:
        return self._vinfo is not None

    @property
    def vinfo(self) -> tuple[int, int]:
        """Encoder'ın kilitli olduğu (width, height)."""
        assert self._vinfo is not None
        return self._vinfo

    @property
    def vinfo_stable_for(self) -> float:
        """Son resolution değişiminden bu yana geçen süre (saniye)."""
        return time.monotonic() - self._vinfo_at if self._vinfo_at else 0.0

    def open_container(self) -> None:
        if self._container is not None or self._vinfo is None:
            return

        self._container = av.open(str(self._path), mode="w", format="matroska")

        w, h = self._vinfo
        vs = self._container.add_stream("libvpx", rate=30)
        ctx = vs.codec_context
        ctx.width    = w
        ctx.height   = h
        ctx.pix_fmt  = "yuv420p"
        ctx.bit_rate = 2_000_000  # 2 Mbps — yasal kanıt kalitesi
        ctx.options["deadline"]  = "realtime"
        ctx.options["cpu-used"]  = "4"
        ctx.options["lag-in-frames"] = "0"
        self._vstr = vs
        logger.info("Video stream: %dx%d @ 2 Mbps VP8", w, h)

        if self._ainfo is not None:
            sr, ch = self._ainfo
            as_ = self._container.add_stream("libopus")
            ctx  = as_.codec_context
            ctx.sample_rate = sr
            ctx.layout      = "stereo" if ch >= 2 else "mono"
            ctx.format      = "s16"
            self._astr  = as_
            self._afifo = av.AudioFifo()
            logger.info("Audio stream: %d Hz %d ch Opus", sr, ch)

        logger.info("MKV container açıldı: %s", self._path.name)

    def write_video(self, av_frame: av.VideoFrame) -> int:
        if self._vstr is None:
            return 0
        av_frame.pts = self._vpts
        self._vpts  += 1
        count = 0
        for pkt in self._vstr.encode(av_frame):
            self._container.mux(pkt)
            count += 1
        return count

    def write_audio(self, av_frame: av.AudioFrame) -> None:
        if self._astr is None or self._afifo is None:
            return
        self._afifo.write(av_frame)
        frame_size = self._astr.codec_context.frame_size or 960
        while self._afifo.samples >= frame_size:
            chunk = self._afifo.read(frame_size)
            if chunk is None:
                break
            chunk.pts = self._apts
            self._apts += frame_size
            for pkt in self._astr.encode(chunk):
                self._container.mux(pkt)

    def close(self) -> None:
        if self._container is None:
            return
        try:
            if self._vstr:
                for pkt in self._vstr.encode(None):
                    self._container.mux(pkt)
            if self._astr:
                for pkt in self._astr.encode(None):
                    self._container.mux(pkt)
            self._container.close()
            logger.info("MKV container kapatıldı")
        except Exception as exc:
            logger.warning("Container kapatma hatası: %s", exc)


# ── Ana kayıt döngüsü ─────────────────────────────────────────────────────────

async def _run(
    room_name: str, ws_url: str, api_key: str, api_secret: str,
    output: Path, stop_evt: asyncio.Event,
) -> None:
    token    = _make_token(room_name, api_key, api_secret)
    writer   = MKVWriter(output)
    room     = rtc.Room()
    open_evt = asyncio.Event()   # container açıldıktan sonra set
    all_tasks: list[asyncio.Task] = []

    # ── Video kaydedici ────────────────────────────────────────────────────
    async def _record_video(track: rtc.RemoteVideoTrack) -> None:
        import numpy as np
        try:
            # BGRA: padding yok, stride = width*4 — I420'nin stride sorununu önler
            vs = rtc.VideoStream(track, format=rtc.VideoBufferType.BGRA)
            vframe_count = 0
            async for event in vs:
                lk = event.frame
                vframe_count += 1
                if vframe_count <= 3:
                    logger.info("VIDEO frame #%d: %dx%d", vframe_count, lk.width, lk.height)
                writer.hint_video(lk.width, lk.height)
                await open_evt.wait()
                # BGRA numpy dizisi → av.VideoFrame → yuv420p
                arr = np.frombuffer(bytes(lk.data), dtype=np.uint8).reshape(lk.height, lk.width, 4)
                frame = av.VideoFrame.from_ndarray(arr, format="bgra")
                enc_w, enc_h = writer.vinfo
                if lk.width != enc_w or lk.height != enc_h:
                    # dynacast kalite geçişi — encoder boyutuna ölçekle
                    frame = frame.reformat(width=enc_w, height=enc_h, format="yuv420p")
                else:
                    frame = frame.reformat(format="yuv420p")
                pkts = writer.write_video(frame)
                if vframe_count <= 3:
                    logger.info("VIDEO encode → %d paket (frame=%d)", pkts, vframe_count)
        except Exception as exc:
            logger.error("_record_video hata: %s", exc, exc_info=True)

    # ── Ses kaydedici ──────────────────────────────────────────────────────
    async def _record_audio(track: rtc.RemoteAudioTrack) -> None:
        try:
            ast = rtc.AudioStream(track)
            aframe_count = 0
            async for event in ast:
                lk = event.frame
                aframe_count += 1
                if aframe_count <= 3:
                    logger.info("AUDIO frame #%d: %dHz %dch %d samples",
                                aframe_count, lk.sample_rate, lk.num_channels, lk.samples_per_channel)
                writer.hint_audio(lk.sample_rate, lk.num_channels)
                await open_evt.wait()
                frame = av.AudioFrame(
                    format="s16",
                    layout="stereo" if lk.num_channels >= 2 else "mono",
                    samples=lk.samples_per_channel,
                )
                frame.sample_rate = lk.sample_rate
                frame.planes[0].update(bytes(lk.data))
                writer.write_audio(frame)
        except Exception as exc:
            logger.error("_record_audio hata: %s", exc, exc_info=True)

    # ── Container koordinatörü ─────────────────────────────────────────────
    async def _open_when_ready() -> None:
        """Video kalitesi stabilize olunca container açar.

        dynacast nedeniyle HIGH simulcast layer subscription'dan ~500ms-2s
        sonra başlar. İlk frame gelince resolution izlemeye başlar;
        _QUALITY_STABLE_S boyunca değişmezse (ya da _QUALITY_TIMEOUT_S
        geçerse) mevcut kaliteyle container açar.
        """
        # 1. İlk video hint gelene kadar bekle
        for _ in range(70):   # max 3.5s
            if writer.has_video_hint:
                break
            await asyncio.sleep(0.05)
        else:
            logger.error("Video track bilgisi alınamadı, container açılmıyor")
            stop_evt.set()
            return

        # 2. Resolution _QUALITY_STABLE_S boyunca sabit kalana kadar bekle
        for _ in range(int(_QUALITY_TIMEOUT_S / 0.05)):
            if writer.vinfo_stable_for >= _QUALITY_STABLE_S:
                break
            await asyncio.sleep(0.05)

        w, h = writer.vinfo
        logger.info("Video kalitesi sabitlendi: %dx%d (%.1fs sabit)", w, h, writer.vinfo_stable_for)
        await asyncio.sleep(0.15)   # audio hint penceresi
        writer.open_container()
        open_evt.set()

    # ── Oda olayları ───────────────────────────────────────────────────────
    @room.on("track_subscribed")
    def on_track_subscribed(track, publication, participant):
        logger.info(
            "Track abone oldu: kind=%s participant=%s",
            track.kind, participant.identity,
        )
        if isinstance(track, rtc.RemoteVideoTrack):
            # Simulcast HIGH layer iste
            publication.set_video_quality(rtc.VideoQuality.VIDEO_QUALITY_HIGH)
            all_tasks.append(asyncio.ensure_future(_record_video(track)))
        elif isinstance(track, rtc.RemoteAudioTrack):
            all_tasks.append(asyncio.ensure_future(_record_audio(track)))

    @room.on("participant_disconnected")
    def on_participant_disconnected(participant):
        logger.info("Katılımcı ayrıldı: %s", participant.identity)
        if not room.remote_participants:
            logger.info("Oda boşaldı, kayıt durduruluyor")
            stop_evt.set()

    @room.on("disconnected")
    def on_disconnected(reason):
        logger.info("Bağlantı kesildi: %s", reason)
        stop_evt.set()

    # ── Bağlan ────────────────────────────────────────────────────────────
    logger.info("Bağlanılıyor | room=%s ws=%s", room_name, ws_url)
    await room.connect(
        ws_url, token,
        options=rtc.RoomOptions(auto_subscribe=True),
    )
    logger.info("Bağlandı | katılımcılar=%d", len(room.remote_participants))

    all_tasks.append(asyncio.ensure_future(_open_when_ready()))

    # ── İzleme ────────────────────────────────────────────────────────────
    async def _monitor() -> None:
        elapsed = 0
        while not stop_evt.is_set():
            await asyncio.sleep(10)
            elapsed += 10
            size_mb = output.stat().st_size / 1_048_576 if output.exists() else 0
            logger.info(
                "MONITOR | t=%ds participants=%d output=%.1f MB",
                elapsed, len(room.remote_participants), size_mb,
            )

    async def _timeout() -> None:
        await asyncio.sleep(_MAX_DURATION_S)
        logger.warning("Maksimum süre aşıldı (%ds), durduruluyor", _MAX_DURATION_S)
        stop_evt.set()

    all_tasks.append(asyncio.ensure_future(_monitor()))
    all_tasks.append(asyncio.ensure_future(_timeout()))

    await stop_evt.wait()

    # ── Temizlik ──────────────────────────────────────────────────────────
    for task in all_tasks:
        task.cancel()
    await asyncio.gather(*all_tasks, return_exceptions=True)

    writer.close()
    await room.disconnect()

    if output.exists():
        logger.info(
            "Kayıt tamamlandı | %s (%.1f MB)",
            output.name, output.stat().st_size / 1_048_576,
        )
    else:
        logger.warning("Çıktı dosyası oluşturulmadı: %s", output)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="LiveKit room kaydedici (livekit-rtc)")
    parser.add_argument("--room",       required=True)
    parser.add_argument("--ws-url",     required=True)
    parser.add_argument("--api-key",    required=True)
    parser.add_argument("--api-secret", required=True)
    parser.add_argument("--output",     required=True)
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    log_path = output.with_suffix(".log")
    fh = logging.FileHandler(str(log_path))
    fh.setFormatter(logging.Formatter(
        "%(asctime)s [livekit-subscriber] %(levelname)s %(message)s"
    ))
    fh.setLevel(logging.DEBUG)
    logging.getLogger().addHandler(fh)

    loop     = asyncio.new_event_loop()
    stop_evt = asyncio.Event()

    def _on_signal(*_):
        logger.info("Sinyal alındı, durduruluyor")
        loop.call_soon_threadsafe(stop_evt.set)

    signal.signal(signal.SIGTERM, _on_signal)
    signal.signal(signal.SIGINT,  _on_signal)

    try:
        loop.run_until_complete(_run(
            room_name  = args.room,
            ws_url     = args.ws_url,
            api_key    = args.api_key,
            api_secret = args.api_secret,
            output     = output,
            stop_evt   = stop_evt,
        ))
    except Exception as exc:
        logger.error("Hata: %s", exc)
        sys.exit(1)
    finally:
        loop.close()


if __name__ == "__main__":
    main()
