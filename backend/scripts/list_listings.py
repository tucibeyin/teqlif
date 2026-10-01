"""
Tüm ilanları listeler.

VPS'de çalıştır:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate

  python scripts/list_listings.py              # tüm aktif ilanlar
  python scripts/list_listings.py --all        # silinmiş/pasif dahil
  python scripts/list_listings.py --user tuci  # username'e göre filtrele
  python scripts/list_listings.py --id 42      # tek ilan detayı
"""
import asyncio, sys, os, argparse
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

parser = argparse.ArgumentParser()
parser.add_argument("--all",  action="store_true", help="Pasif/silinmiş dahil")
parser.add_argument("--user", default=None,        help="Username filtresi (kısmi eşleşme)")
parser.add_argument("--id",   type=int, default=None, help="Tek ilan ID")
args = parser.parse_args()


async def main():
    from sqlalchemy import select
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing
    from app.models.user import User

    async with AsyncSessionLocal() as db:
        q = (
            select(
                Listing.id,
                Listing.title,
                Listing.category,
                Listing.price,
                Listing.is_active,
                Listing.is_deleted,
                Listing.is_highlight,
                Listing.is_sponsored if hasattr(Listing, "is_sponsored") else Listing.id.label("_dummy"),
                User.username,
                User.id.label("user_id"),
            )
            .join(User, User.id == Listing.user_id)
            .order_by(Listing.id.desc())
        )

        if args.id:
            q = q.where(Listing.id == args.id)
        elif not args.all:
            q = q.where(Listing.is_active == True, Listing.is_deleted == False)

        if args.user:
            q = q.where(User.username.ilike(f"%{args.user}%"))

        rows = (await db.execute(q)).all()

        if not rows:
            print("İlan bulunamadı.")
            return

        # --- Tek ilan detayı ---
        if args.id and rows:
            r = rows[0]
            print(f"\n{'━'*50}")
            print(f"  İLAN DETAYI  (ID={r.id})")
            print(f"{'━'*50}")
            print(f"  Başlık   : {r.title}")
            print(f"  Sahip    : @{r.username}  (user_id={r.user_id})")
            print(f"  Kategori : {r.category}")
            print(f"  Fiyat    : {r.price}")
            print(f"  Aktif    : {r.is_active}  |  Silindi: {r.is_deleted}")
            print(f"  Öne Çıkan: {r.is_highlight}")
            print()
            return

        # --- Tablo ---
        print(f"\n{'━'*80}")
        label = "TÜM İLANLAR" if args.all else "AKTİF İLANLAR"
        if args.user:
            label += f"  (kullanıcı: {args.user})"
        print(f"  {label}  ({len(rows)} adet)")
        print(f"{'━'*80}")
        print(f"{'ID':>5}  {'Sahip':<16}  {'Kategori':<14}  {'Fiyat':>8}  {'A':>1}  {'D':>1}  Başlık")
        print(f"{'─'*80}")
        for r in rows:
            aktif  = "✓" if r.is_active  else "✗"
            silindi = "✓" if r.is_deleted else "—"
            fiyat  = f"{r.price:.0f}₺" if r.price else "—"
            baslik = (r.title or "")[:32]
            print(f"{r.id:>5}  {('@'+r.username):<16}  {(r.category or '—'):<14}  {fiyat:>8}  {aktif}  {silindi}  {baslik}")
        print()


asyncio.run(main())
