import asyncio
import os
import sys
import random
from datetime import datetime, timedelta, timezone
from faker import Faker

# Add backend directory to sys.path
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(backend_dir)

from dotenv import load_dotenv
load_dotenv(os.path.join(backend_dir, ".env"))

from sqlalchemy.ext.asyncio import AsyncSession
from passlib.context import CryptContext

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.listing import Listing
from app.models.stream import LiveStream, LiveStreamViewer
from app.models.auction import Auction
from app.models.bid import Bid
from app.models.purchase import Purchase
from app.models.like import ListingLike, StreamLike

fake = Faker('tr_TR')
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ─── MOCK DATA SETS ──────────────────────────────────────────────────────────
CATEGORIES = {
    "Elektronik": [
        {"brand": "Apple", "models": ["iPhone 13", "iPhone 14 Pro", "iPhone 15", "MacBook Air M1", "MacBook Pro M2"]},
        {"brand": "Samsung", "models": ["Galaxy S22", "Galaxy S23 Ultra", "Galaxy Z Fold 4"]},
        {"brand": "Sony", "models": ["PlayStation 5", "Alpha a7 III"]},
        {"brand": "Nintendo", "models": ["Switch OLED"]},
    ],
    "Giyim": [
        {"brand": "Nike", "models": ["Air Force 1", "Air Jordan 1", "Dunk Low"]},
        {"brand": "Adidas", "models": ["Yeezy Boost 350", "Stan Smith", "Superstar"]},
        {"brand": "Zara", "models": ["Deri Ceket", "Kaban"]},
    ],
    "Saat": [
        {"brand": "Rolex", "models": ["Submariner", "Datejust", "Daytona"]},
        {"brand": "Seiko", "models": ["5 Sports", "Prospex"]},
        {"brand": "Casio", "models": ["G-Shock", "Edifice"]},
    ]
}
CONDITIONS = ["Sıfır", "Yeni Gibi", "İkinci El", "Yıpranmış"]

# ─── HELPER FUNCTIONS ────────────────────────────────────────────────────────
def random_date(start_days_ago=180):
    start = datetime.now(timezone.utc) - timedelta(days=start_days_ago)
    return start + timedelta(seconds=random.randint(0, start_days_ago * 24 * 3600))

# ─── MAIN SCRIPT ─────────────────────────────────────────────────────────────
async def seed_data():
    print("🚀 Mock Data Seeding Başlıyor...")
    
    async with AsyncSessionLocal() as session:
        # 0. CUSTOM USER
        print("💡 Test için kendi kullanıcı adınızı ve şifrenizi belirleyin:")
        custom_username = input("Username: ").strip() or "testuser"
        custom_password = input("Password: ").strip() or "Teqlif123!"
        custom_pw_hash = pwd_context.hash(custom_password)
        
        from sqlalchemy import select
        existing_user_stmt = select(User).where(User.username == custom_username)
        existing_user_result = await session.execute(existing_user_stmt)
        existing_user = existing_user_result.scalars().first()
        
        # 1. USERS
        print("👤 1/6: Kullanıcılar oluşturuluyor (100 adet)...")
        users = []
        new_users_to_add = []
        default_pw = pwd_context.hash("Teqlif123!")
        
        if existing_user:
            print(f"✅ '{custom_username}' zaten var, mevcut hesap kullanılacak.")
            users.append(existing_user)
        else:
            custom_user = User(
                username=custom_username,
                email=f"{custom_username}{random.randint(100, 999)}@example.com",
                hashed_password=custom_pw_hash,
                full_name="Test Kullanıcısı",
                phone="555" + str(random.randint(1000000, 9999999)),
                bio="Geliştirici test hesabı",
                profile_image_url=f"https://i.pravatar.cc/150?u={random.randint(1, 1000)}",
                is_premium=True
            )
            new_users_to_add.append(custom_user)
            users.append(custom_user)
            
        for i in range(1, 100):
            is_pro = random.random() < 0.25 # 25% pro
            
            user = User(
                    username=fake.user_name() + str(random.randint(10, 9999)),
                    email=fake.email(),
                    hashed_password=default_pw,
                    full_name=fake.name(),
                    phone=fake.phone_number()[:20],
                    bio=fake.sentence()[:150] if random.random() > 0.5 else None,
                    profile_image_url=f"https://i.pravatar.cc/150?u={random.randint(1, 1000)}",
                    is_premium=is_pro
                )
            new_users_to_add.append(user)
            users.append(user)
            
        if new_users_to_add:
            session.add_all(new_users_to_add)
            try:
                await session.flush() # flush to get user IDs
            except Exception as e:
                print(f"Kullanıcı oluşturulurken hata (Büyük ihtimalle email çakışması, tekrar deneyin): {e}")
                return
        
        # 2. LISTINGS
        print("📦 2/6: İlanlar oluşturuluyor (~2000 adet)...")
        listings = []
        for user in users:
            # Her kullanıcıya 10-30 arası ilan
            for _ in range(random.randint(10, 30)):
                cat = random.choice(list(CATEGORIES.keys()))
                brand_dict = random.choice(CATEGORIES[cat])
                brand = brand_dict["brand"]
                model = random.choice(brand_dict["models"])
                
                # Fiyat algoritmasını eğitmek için rastgele dalgalanan fiyatlar
                base_price = random.uniform(500, 50000)
                price = round(base_price + random.uniform(-0.1, 0.1) * base_price, 2)
                
                listing = Listing(
                    user_id=user.id,
                    title=f"{brand} {model} {fake.word().capitalize()}",
                    description=fake.text(max_nb_chars=200),
                    price=price,
                    category=cat,
                    brand=brand,
                    model_name=model,
                    condition=random.choice(CONDITIONS),
                    location=fake.city(),
                    image_url=f"https://picsum.photos/seed/{random.randint(1,10000)}/800/600",
                    is_active=random.random() > 0.3, # %70 aktif
                    created_at=random_date()
                )
                listings.append(listing)
        session.add_all(listings)
        await session.flush()

        # 3. LIVE STREAMS
        print("🎥 3/6: Canlı Yayın Geçmişleri oluşturuluyor (500+ adet)...")
        streams = []
        pro_users = [u for u in users if u.is_premium]
        
        # Sadece bazı kullanıcılar yayın açmış olsun (ör: Pro'lar)
        for user in pro_users:
            for _ in range(random.randint(5, 20)):
                started = random_date()
                ended = started + timedelta(minutes=random.randint(15, 180))
                
                stream = LiveStream(
                    room_name=f"room_{user.id}_{random.randint(1000, 99999)}",
                    title=fake.catch_phrase(),
                    category=random.choice(list(CATEGORIES.keys())),
                    host_id=user.id,
                    is_live=False,
                    viewer_count=random.randint(10, 1000),
                    started_at=started,
                    ended_at=ended,
                    thumbnail_url=f"https://picsum.photos/seed/{random.randint(1,10000)}/800/600"
                )
                streams.append(stream)
        session.add_all(streams)
        await session.flush()
        
        # 4. VIEWERS & LIKES
        print("👥 4/6: Sosyal Etkileşimler ekleniyor (Viewers & Likes)...")
        viewers = []
        stream_likes = []
        listing_likes = []
        
        for stream in streams:
            # Rastgele 5-20 arası izleyici
            audience = random.sample(users, random.randint(5, min(20, len(users))))
            for u in audience:
                viewers.append(LiveStreamViewer(
                    stream_id=stream.id,
                    user_id=u.id,
                    joined_at=stream.started_at + timedelta(minutes=random.randint(1, 10))
                ))
                if random.random() > 0.5:
                    stream_likes.append(StreamLike(
                        stream_id=stream.id,
                        user_id=u.id,
                        created_at=stream.started_at + timedelta(minutes=random.randint(5, 15))
                    ))
                    
        for listing in random.sample(listings, min(500, len(listings))):
            fans = random.sample(users, random.randint(1, 10))
            for u in fans:
                listing_likes.append(ListingLike(
                    listing_id=listing.id,
                    user_id=u.id,
                    created_at=random_date()
                ))
                
        session.add_all(viewers)
        session.add_all(stream_likes)
        session.add_all(listing_likes)
        await session.flush()

        # 5. AUCTIONS & BIDS
        print("⚖️ 5/6: Satışlar, Açık Artırmalar ve Teklifler simüle ediliyor...")
        auctions = []
        bids = []
        purchases = []
        
        for stream in streams:
            # Her yayında 1-5 açık artırma
            stream_listings = random.sample(
                [l for l in listings if l.user_id == stream.host_id], 
                k=min(random.randint(1, 5), len([l for l in listings if l.user_id == stream.host_id]))
            )
            
            for listing in stream_listings:
                start_price = listing.price * 0.5 # Yarı fiyatına başlasın
                auction_end = stream.started_at + timedelta(minutes=random.randint(10, 50))
                
                # Rastgele katılımcılar
                participants = random.sample([u for u in users if u.id != stream.host_id], k=random.randint(2, 5))
                
                # Kazananı belirle
                winner = participants[-1]
                final_price = start_price + random.randint(100, 2000)
                
                auction = Auction(
                    stream_id=stream.id,
                    listing_id=listing.id,
                    item_name=listing.title,
                    start_price=start_price,
                    final_price=final_price,
                    winner_id=winner.id,
                    winner_username=winner.username,
                    bid_count=len(participants) * 2,
                    status="completed",
                    started_at=auction_end - timedelta(minutes=5),
                    ended_at=auction_end
                )
                auctions.append(auction)
        session.add_all(auctions)
        await session.flush()
        
        # Teklifler ve Satın Alma Kayıtları
        for auction in auctions:
            if auction.winner_id:
                bid = Bid(
                    stream_id=auction.stream_id,
                    bidder_id=auction.winner_id,
                    bidder_username=auction.winner_username,
                    amount=auction.final_price,
                    created_at=auction.ended_at - timedelta(seconds=random.randint(1, 30))
                )
                bids.append(bid)
                
                # Listing'i satıldı işaretle
                target_listing = next((l for l in listings if l.id == auction.listing_id), None)
                if target_listing:
                    target_listing.is_active = False
                    target_listing.last_sold_price = auction.final_price
                    target_listing.last_start_price = auction.start_price
                    
                    purchase = Purchase(
                        listing_id=target_listing.id,
                        buyer_id=auction.winner_id,
                        seller_id=target_listing.user_id,
                        price=auction.final_price,
                        created_at=auction.ended_at
                    )
                    purchases.append(purchase)
        
        session.add_all(bids)
        session.add_all(purchases)
        
        print("💾 6/6: Tüm veriler veritabanına işleniyor (Commit)...")
        await session.commit()
        print("✅ Başarılı! Sistem on binlerce mock data ile dolduruldu.")

if __name__ == "__main__":
    asyncio.run(seed_data())
