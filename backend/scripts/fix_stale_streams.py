"""
Hayalet (stale) yayınları tespit eder ve zorla kapatır.
Argümansız: tüm is_live=True ve 5+ dk önce başlamış yayınları tarar.
Argümanlı: belirtilen stream_id'leri kontrol eder.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate

  # Sadece incele (kapatma yok):
  python scripts/fix_stale_streams.py

  # Belirli yayınları incele + zorla kapat:
  python scripts/fix_stale_streams.py --force 850 851
"""
import asyncio, sys, os, argparse
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

parser = argparse.ArgumentParser()
parser.add_argument('stream_ids', nargs='*', type=int, help='Kontrol edilecek stream ID\'ler')
parser.add_argument('--force', action='store_true', help='Stale yayınları zorla kapat')
args = parser.parse_args()


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from datetime import datetime, timezone, timedelta
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.stream import LiveStream

    async with AsyncSessionLocal() as db:

        # ── 1. Yayınları bul ──────────────────────────────────────────────
        sep("1. YAYINLAR")

        if args.stream_ids:
            streams = (await db.execute(
                select(LiveStream).where(LiveStream.id.in_(args.stream_ids))
            )).scalars().all()
        else:
            # 5+ dakika önce başlamış ve hâlâ is_live=True olan tüm yayınlar
            cutoff = datetime.now(timezone.utc) - timedelta(minutes=5)
            streams = (await db.execute(
                select(LiveStream).where(
                    LiveStream.is_live == True,  # noqa
                    LiveStream.started_at <= cutoff,
                )
            )).scalars().all()

        if not streams:
            print("  Stale yayın bulunamadı.")
            return

        now = datetime.now(timezone.utc)
        print(f"  {'ID':>5}  {'is_live':>7}  {'host_id':>7}  {'started_at':>20}  {'Süredir':>10}  room_name")
        print(f"  {'─'*75}")
        for s in streams:
            st = s.started_at
            if st and st.tzinfo is None:
                st = st.replace(tzinfo=timezone.utc)
            elapsed = f"{int((now - st).total_seconds() // 60)} dk" if st else "?"
            print(f"  {s.id:>5}  {'✓ AÇIK' if s.is_live else '✗ kapalı':>7}  {s.host_id:>7}  {str(st)[:19]:>20}  {elapsed:>10}  {s.room_name or '—'}")

        # ── 2. LiveKit oda durumu ─────────────────────────────────────────
        sep("2. LİVEKİT ODA DURUMU")
        try:
            import aiohttp
            from livekit.api import RoomService, ListRoomsRequest
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

            for s in streams:
                if s.room_name in active_rooms:
                    r = active_rooms[s.room_name]
                    print(f"  Stream #{s.id}: LiveKit'te AKTİF — {r.num_participants} katılımcı")
                else:
                    print(f"  Stream #{s.id}: LiveKit'te YOK (oda kapalı veya hiç oluşmadı)")
        except Exception as e:
            print(f"  ⚠ LiveKit API hatası: {e}")

        # ── 3. Zorla kapat ────────────────────────────────────────────────
        if args.force:
            sep("3. ZORLA KAPAT")
            from app.services.stream_service import StreamService
            from app.services.auction_service import AuctionService

            for s in streams:
                if not s.is_live:
                    print(f"  Stream #{s.id}: zaten kapalı, atlandı")
                    continue
                try:
                    room = s.room_name

                    # Yetim açık artırmayı zorla bitir
                    from sqlalchemy import text as sql_text
                    open_auction = (await db.execute(sql_text("""
                        SELECT id FROM auctions WHERE stream_id = :sid AND status = 'active'
                    """), {"sid": s.id})).fetchone()

                    if open_auction:
                        print(f"  Stream #{s.id}: açık auction #{open_auction[0]} var — sistem olarak bitiriliyor")
                        await db.execute(sql_text("""
                            UPDATE auctions SET status='completed', ended_at=NOW()
                            WHERE id = :aid AND status='active'
                        """), {"aid": open_auction[0]})

                    # Yayını kapat
                    s.is_live = False
                    s.ended_at = datetime.now(timezone.utc)
                    await db.commit()
                    print(f"  Stream #{s.id}: ✅ KAPATILDI  (room: {room})")

                    # WebSocket bağlantılarına bildir (varsa)
                    try:
                        from app.core.connection_manager import manager
                        await manager.broadcast_to_stream(s.id, {"type": "stream_ended"})
                    except Exception:
                        pass  # WS bağlantısı yoksa önemli değil

                except Exception as e:
                    await db.rollback()
                    print(f"  Stream #{s.id}: ⚠ HATA — {e}")
        else:
            print(f"\n  💡 Zorla kapatmak için: python scripts/fix_stale_streams.py --force {' '.join(str(s.id) for s in streams if s.is_live)}")

    print()


asyncio.run(main())
