"""
Hayalet yayınların neden kapanmadığını analiz eder.
Belirtilen stream_id'ler için tam tanısal rapor verir.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/debug_stale_stream.py 850 851
"""
import asyncio, sys, os, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

STREAM_IDS = [int(x) for x in sys.argv[1:]] if len(sys.argv) > 1 else [850, 851]


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from datetime import datetime, timezone
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.stream import LiveStream

    sep(f"STREAM DURUMU — #{' #'.join(str(i) for i in STREAM_IDS)}")
    async with AsyncSessionLocal() as db:
        streams = (await db.execute(
            select(LiveStream).where(LiveStream.id.in_(STREAM_IDS))
        )).scalars().all()

        now = datetime.now(timezone.utc)
        for s in streams:
            st = s.started_at
            if st and st.tzinfo is None:
                st = st.replace(tzinfo=timezone.utc)
            elapsed = int((now - st).total_seconds() // 60) if st else 0
            print(f"\n  Stream #{s.id}")
            print(f"    is_live     : {s.is_live}")
            print(f"    host_id     : {s.host_id}  (LiveKit identity beklenen: '{s.host_id}')")
            print(f"    started_at  : {str(st)[:19]} ({elapsed} dk önce)")
            print(f"    ended_at    : {s.ended_at or 'NULL — hâlâ açık'}")
            print(f"    room_name   : {s.room_name}")

            # Yetim açık artırma var mı?
            auctions = (await db.execute(text("""
                SELECT id, status, winner_username FROM auctions
                WHERE stream_id = :sid ORDER BY id DESC LIMIT 5
            """), {"sid": s.id})).fetchall()
            if auctions:
                print(f"    Açık artırmalar:")
                for a in auctions:
                    print(f"      auction #{a.id}: status={a.status}, winner={a.winner_username or '—'}")

    # ── LiveKit oda durumu ──────────────────────────────────────────────
    sep("LİVEKİT ODA DURUMU")
    try:
        import aiohttp
        from livekit.api.room_service import RoomService, ListRoomsRequest
        from app.core.config import settings

        async with aiohttp.ClientSession() as session:
            svc = RoomService(
                session,
                settings.livekit_api_base,
                settings.livekit_api_key,
                settings.livekit_api_secret,
            )
            res = await svc.list_rooms(ListRoomsRequest())
            active_rooms = {r.name: r for r in res.rooms}

        async with AsyncSessionLocal() as db:
            streams = (await db.execute(
                select(LiveStream).where(LiveStream.id.in_(STREAM_IDS))
            )).scalars().all()

            for s in streams:
                if s.room_name in active_rooms:
                    r = active_rooms[s.room_name]
                    print(f"  Stream #{s.id}: LiveKit'te ✓ AKTİF ({r.num_participants} katılımcı)")
                    print(f"    → participant_left webhook GELMEMİŞ veya işlenmemiş")
                else:
                    print(f"  Stream #{s.id}: LiveKit'te ✗ YOK (oda kapalı/silinmiş)")
                    print(f"    → room_finished webhook işlenmemiş olabilir")
                    print(f"    → VEYA LiveKit bu odayı hiç oluşturmadı")
    except Exception as e:
        print(f"  ⚠ LiveKit API erişim hatası: {e}")

    # ── Redis: host_reconnect bayrağı ──────────────────────────────────
    sep("REDİS — host_reconnect BAYRAĞI")
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        for sid in STREAM_IDS:
            val = await redis.get(f"live:host_reconnect:{sid}")
            if val:
                ts = float(val)
                dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                print(f"  Stream #{sid}: host_reconnect = {dt.strftime('%H:%M:%S')} (varsa grace period iptal olur!)")
            else:
                print(f"  Stream #{sid}: host_reconnect = YOK (doğru — host geri dönmemiş)")
    except Exception as e:
        print(f"  ⚠ Redis hatası: {e}")

    # ── Son webhook logları ─────────────────────────────────────────────
    sep("ÖNERİ")
    print("  Kontrol edilecekler (sırasıyla):")
    print("  1. LiveKit oda durumuna bak (yukarıda)")
    print("  2. Backend loglarında 'participant_left' veya 'STREAMS] Host ayrıldı' ara:")
    print("     sudo journalctl -u teqlif -n 500 | grep -i 'participant_left\\|Host ayrıldı\\|stream_id=850\\|stream_id=851'")
    print("  3. Eğer log yoksa: LiveKit webhook hiç gelmemiş (LiveKit konfigürasyon sorunu)")
    print("  4. Eğer log varsa ama yayın kapanmadıysa: sleep(120) süresi içinde servis yeniden başlatılmış")
    print()
    print("  Hemen kapatmak için:")
    print(f"  python scripts/fix_stale_streams.py --force {' '.join(str(i) for i in STREAM_IDS)}")


asyncio.run(main())
