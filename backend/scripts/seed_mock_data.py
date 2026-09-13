import asyncio
import json
import os
import sys
import random
import uuid
from datetime import datetime, timedelta, timezone
from faker import Faker

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(backend_dir)

from dotenv import load_dotenv
load_dotenv(os.environ.get("TEQLIF_ENV_FILE", ""))

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from passlib.context import CryptContext

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.listing import Listing
from app.models.enums import ListingStatus, SearchAlertStatus
from app.models.stream import LiveStream, LiveStreamViewer
from app.models.auction import Auction
from app.models.bid import Bid
from app.models.purchase import Purchase
from app.models.like import ListingLike, StreamLike, StoryLike
from app.models.analytics import AnalyticsEvent, UserInteraction
from app.models.follow import Follow
from app.models.favorite import Favorite
from app.models.listing_offer import ListingOffer
from app.models.listing_impression import ListingImpression
from app.models.notification import Notification
from app.models.message_thread import MessageThread
from app.models.message import DirectMessage
from app.models.rating import Rating
from app.models.user_interest import UserInterest
from app.models.tuci_transaction import TuciTransaction
from app.models.story import Story, StoryView
from app.models.search_alert import SearchAlert
from app.models.referral import Referral

fake = Faker('tr_TR')
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

CATEGORIES = {
    "electronics": [
        {"brand": "Apple", "models": ["iPhone 13", "iPhone 14 Pro", "iPhone 15", "MacBook Air M1", "MacBook Pro M2"]},
        {"brand": "Samsung", "models": ["Galaxy S22", "Galaxy S23 Ultra", "Galaxy Z Fold 4"]},
        {"brand": "Sony", "models": ["PlayStation 5", "Alpha a7 III"]},
        {"brand": "Nintendo", "models": ["Switch OLED"]},
    ],
    "vehicles": [
        {"brand": "Mercedes", "models": ["C200", "E250", "GLA"]},
        {"brand": "BMW", "models": ["320i", "520d", "X5"]},
        {"brand": "Audi", "models": ["A3", "A4", "Q5"]},
    ],
    "real_estate": [
        {"brand": "Satılık Daire", "models": ["3+1", "2+1", "1+1"]},
        {"brand": "Kiralık Daire", "models": ["3+1", "2+1", "Studio"]},
    ],
    "fashion": [
        {"brand": "Nike", "models": ["Air Force 1", "Air Jordan 1", "Dunk Low"]},
        {"brand": "Adidas", "models": ["Yeezy Boost 350", "Stan Smith", "Superstar"]},
        {"brand": "Zara", "models": ["Deri Ceket", "Kaban"]},
    ],
    "sports": [
        {"brand": "Decathlon", "models": ["Çadır", "Bisiklet", "Dambıl Seti"]},
        {"brand": "Under Armour", "models": ["Koşu Ayakkabısı", "Spor Çantası"]},
    ],
    "books": [
        {"brand": "Roman", "models": ["Bilim Kurgu", "Klasik", "Polisiye"]},
        {"brand": "Plak", "models": ["Rock", "Caz", "Pop"]},
    ],
    "home": [
        {"brand": "IKEA", "models": ["Koltuk", "Masa", "Kitaplık"]},
        {"brand": "Bosch", "models": ["Buzdolabı", "Çamaşır Makinesi", "Bulaşık Makinesi"]},
    ],
    "other": [
        {"brand": "Rolex", "models": ["Submariner", "Datejust", "Daytona"]},
        {"brand": "Seiko", "models": ["5 Sports", "Prospex"]},
        {"brand": "Casio", "models": ["G-Shock", "Edifice"]},
    ],
}
CONDITIONS = ["Sıfır", "Yeni Gibi", "İkinci El", "Yıpranmış"]
CATEGORY_NAMES = list(CATEGORIES.keys())

NOTIF_TYPES = [
    ("new_offer", "Yeni Teklif", "İlanınıza yeni bir teklif geldi"),
    ("offer_accepted", "Teklif Kabul Edildi", "Teklifiniz satıcı tarafından kabul edildi"),
    ("new_follower", "Yeni Takipçi", "Sizi takip etmeye başladı"),
    ("listing_liked", "İlan Beğenildi", "İlanınız beğenildi"),
    ("auction_won", "Açık Artırma Kazandınız", "Tebrikler! Açık artırmayı kazandınız"),
    ("stream_starting", "Yayın Başlıyor", "Takip ettiğiniz satıcı yayına başladı"),
    ("price_drop", "Fiyat Düştü", "Favorilediğiniz ilanda fiyat düşüşü var"),
    ("message_received", "Yeni Mesaj", "Yeni bir mesajınız var"),
]

SEARCH_QUERIES = {
    "electronics": ["iphone", "samsung galaxy", "laptop", "macbook", "playstation", "gaming"],
    "vehicles": ["bmw", "mercedes", "ikinci el araba", "suv", "sedan"],
    "fashion": ["nike", "adidas", "spor ayakkabı", "deri ceket", "kaban"],
    "home": ["ikea koltuk", "buzdolabı", "çamaşır makinesi", "masa"],
    "sports": ["bisiklet", "dambıl", "çadır", "koşu ayakkabısı"],
    "books": ["roman", "bilim kurgu", "klasik kitap", "plak"],
    "real_estate": ["kiralık daire", "satılık 2+1", "istanbul daire"],
    "other": ["rolex", "saat", "vintage"],
}


def random_date(start_days_ago: int = 180) -> datetime:
    start = datetime.now(timezone.utc) - timedelta(days=start_days_ago)
    return start + timedelta(seconds=random.randint(0, start_days_ago * 24 * 3600))


def recent_date(days: int = 7) -> datetime:
    start = datetime.now(timezone.utc) - timedelta(days=days)
    return start + timedelta(seconds=random.randint(0, days * 24 * 3600))


async def seed_clickhouse(
    users: list,
    listings_by_cat: dict[str, list],
    streams: list,
    auctions: list,
    user_preferred_cats: dict[int, list[str]],
) -> None:
    print("🔶 ClickHouse bağlantısı kuruluyor...")
    try:
        import clickhouse_connect
        from app.config import settings
        ch = await clickhouse_connect.get_async_client(
            host=settings.clickhouse_host,
            port=settings.clickhouse_port,
            database=settings.clickhouse_db,
            connect_timeout=10,
            send_receive_timeout=60,
        )
        print("✅ ClickHouse bağlandı.")
    except Exception as e:
        print(f"⚠️  ClickHouse bağlanamadı, atlanıyor: {e}")
        return

    def ch_ts(dt: datetime) -> str:
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    # ── feed_analytics ─────────────────────────────────────────────────────────
    print("  📊 feed_analytics dolduruluyor...")
    fa_rows = []
    for user in users:
        uid = user.id
        preferred = user_preferred_cats.get(uid, random.sample(CATEGORY_NAMES, 2))
        for _ in range(random.randint(30, 70)):
            # %70 tercih edilen kategori, %30 keşif
            cat = random.choice(preferred) if random.random() < 0.7 else random.choice(CATEGORY_NAMES)
            cat_listings = listings_by_cat.get(cat, [])
            if not cat_listings:
                continue
            lid = random.choice(cat_listings)
            event_type = random.choices(
                ["impression", "click", "skip"],
                weights=[60, 25, 15],
            )[0]
            dwell = 0
            if event_type == "impression":
                dwell = random.choice([
                    random.randint(4000, 15000),  # dwell >3s → +2
                    random.randint(200, 1500),    # hızlı geçiş
                ])
            slot = random.randint(0, 20)
            ts = ch_ts(recent_date(7))
            fa_rows.append([
                ts, str(uid), str(lid), event_type,
                dwell, "listing", slot, cat, "", "",
            ])

    if fa_rows:
        await ch.insert(
            "feed_analytics",
            fa_rows,
            column_names=["timestamp", "user_id", "listing_id", "event_type",
                          "dwell_time_ms", "content_type", "slot_index",
                          "stream_category", "listing_condition", "listing_subcategory"],
        )
        print(f"  ✅ feed_analytics: {len(fa_rows)} satır")

    # ── user_events ─────────────────────────────────────────────────────────────
    print("  📊 user_events dolduruluyor...")
    ue_rows = []
    for user in users:
        uid = user.id
        preferred = user_preferred_cats.get(uid, random.sample(CATEGORY_NAMES, 2))
        # detail_dwell: ilanı 30+ saniye inceledi
        for _ in range(random.randint(3, 10)):
            cat = random.choice(preferred)
            cat_listings = listings_by_cat.get(cat, [])
            if not cat_listings:
                continue
            lid = random.choice(cat_listings)
            duration = round(random.uniform(30.0, 180.0), 1)
            ts = ch_ts(recent_date(14))
            ue_rows.append([uid, lid, "listing", "detail_dwell", None, duration, "", ts, ""])
        # bid_hesitation: teklif yazmaya başladı ama göndermedi
        for _ in range(random.randint(1, 5)):
            cat = random.choice(preferred)
            cat_listings = listings_by_cat.get(cat, [])
            if not cat_listings:
                continue
            lid = random.choice(cat_listings)
            price_point = round(random.uniform(500, 20000), 2)
            ts = ch_ts(recent_date(14))
            ue_rows.append([uid, lid, "listing", "bid_hesitation", price_point, None, "", ts, ""])

    if ue_rows:
        await ch.insert(
            "user_events",
            ue_rows,
            column_names=["user_id", "item_id", "item_type", "event_type",
                          "price_point", "duration_seconds", "metadata", "timestamp", "subcategory"],
        )
        print(f"  ✅ user_events: {len(ue_rows)} satır")

    # ── search_events ────────────────────────────────────────────────────────────
    print("  📊 search_events dolduruluyor...")
    se_rows = []
    for user in users:
        uid = user.id
        preferred = user_preferred_cats.get(uid, random.sample(CATEGORY_NAMES, 2))
        for _ in range(random.randint(5, 15)):
            cat = random.choice(preferred) if random.random() < 0.7 else random.choice(CATEGORY_NAMES)
            queries = SEARCH_QUERIES.get(cat, ["ilan"])
            query = random.choice(queries)
            result_count = random.randint(0, 200)
            intent = random.choice(["browse", "buy", "compare", ""])
            ts = ch_ts(recent_date(30))
            se_rows.append([ts, uid, query, cat, result_count, intent, ""])

    if se_rows:
        await ch.insert(
            "search_events",
            se_rows,
            column_names=["timestamp", "user_id", "query", "category",
                          "result_count", "intent", "subcategory"],
        )
        print(f"  ✅ search_events: {len(se_rows)} satır")

    # ── swipe_live_events ────────────────────────────────────────────────────────
    print("  📊 swipe_live_events dolduruluyor...")
    sle_rows = []
    for stream in random.sample(streams, min(50, len(streams))):
        stream_cat = stream.category or "other"
        cat_listings = listings_by_cat.get(stream_cat, [])
        if not cat_listings:
            continue
        viewers = random.sample([u.id for u in users], random.randint(5, 20))
        for uid in viewers:
            session = uuid.uuid4().hex[:12]
            seen = random.randint(3, 15)
            for slot_i in range(seen):
                lid = random.choice(cat_listings)
                event_type = random.choices(
                    ["impression", "click", "skip", "swipe_next"],
                    weights=[50, 20, 20, 10],
                )[0]
                dwell = random.randint(500, 8000) if event_type in ("impression", "click") else 0
                ts = ch_ts(random_date(30))
                sle_rows.append([
                    uid, stream.id, lid, event_type, dwell,
                    stream_cat, stream_cat, random.choice(CONDITIONS),
                    seen, slot_i, session, ts, "", "",
                ])

    if sle_rows:
        await ch.insert(
            "swipe_live_events",
            sle_rows,
            column_names=["user_id", "stream_id", "listing_id", "event_type", "dwell_ms",
                          "stream_category", "listing_category", "listing_condition",
                          "listings_seen", "slot_index", "session_id", "timestamp",
                          "stream_subcategory", "listing_subcategory"],
        )
        print(f"  ✅ swipe_live_events: {len(sle_rows)} satır")

    # ── direct_sale_events ───────────────────────────────────────────────────────
    print("  📊 direct_sale_events dolduruluyor...")
    dse_rows = []
    for auction in random.sample(auctions, min(100, len(auctions))):
        if not auction.winner_id:
            continue
        viewer_count = random.randint(10, 200)
        cat = random.choice(CATEGORY_NAMES)
        ts = ch_ts(auction.started_at or random_date(60))
        # sale_started
        dse_rows.append([
            "sale_started", auction.id, auction.stream_id, 0,
            auction.winner_id, None, auction.listing_id, cat,
            None, None, None, None, None, viewer_count, None, None, ts,
        ])
        # purchase_completed
        ts2 = ch_ts(auction.ended_at or random_date(60))
        dse_rows.append([
            "purchase_completed", auction.id, auction.stream_id, 0,
            auction.winner_id, None, auction.listing_id, cat,
            1, auction.final_price, auction.final_price, None, None,
            viewer_count, "auction_ended", None, ts2,
        ])

    if dse_rows:
        await ch.insert(
            "direct_sale_events",
            dse_rows,
            column_names=["event_type", "sale_id", "stream_id", "host_id", "user_id",
                          "order_id", "listing_id", "category", "quantity",
                          "unit_price", "total_price", "remaining_stock_before",
                          "remaining_stock_after", "viewer_count", "end_reason",
                          "orders_voided", "created_at"],
        )
        print(f"  ✅ direct_sale_events: {len(dse_rows)} satır")

    print("🔶 ClickHouse seed tamamlandı.")


async def seed_data():
    print("🚀 Mock Data Seeding Başlıyor...")

    async with AsyncSessionLocal() as session:

        # ── 0. CUSTOM USER ─────────────────────────────────────────────────────
        print("💡 Test kullanıcı adı ve şifre:")
        custom_username = input("Username (boş bırakırsan 'testuser'): ").strip() or "testuser"
        custom_password = input("Password (boş bırakırsan 'Teqlif123!'): ").strip() or "Teqlif123!"
        custom_pw_hash = pwd_context.hash(custom_password)

        existing_result = await session.execute(
            select(User).where(User.username == custom_username)
        )
        existing_user = existing_result.scalars().first()

        # ── 1. USERS ────────────────────────────────────────────────────────────
        print("👤 1/20: Kullanıcılar oluşturuluyor (100 adet)...")
        users: list[User] = []
        new_users: list[User] = []
        default_pw = pwd_context.hash("Teqlif123!")

        if existing_user:
            print(f"  ✅ '{custom_username}' mevcut, kullanılıyor.")
            users.append(existing_user)
        else:
            uid = uuid.uuid4().hex[:6]
            custom_user = User(
                username=custom_username,
                email=f"{custom_username}_{uid}@example.com",
                hashed_password=custom_pw_hash,
                full_name="Test Kullanıcısı",
                phone="555" + str(random.randint(1000000, 9999999)),
                bio="Geliştirici test hesabı",
                profile_image_url=f"https://i.pravatar.cc/150?u={random.randint(1, 1000)}",
                is_premium=True,
                tuci_balance=500,
            )
            new_users.append(custom_user)
            users.append(custom_user)

        for _ in range(99):
            uid = uuid.uuid4().hex[:6]
            user = User(
                username=f"{fake.user_name()}_{uid}",
                email=f"{fake.user_name()}_{uid}@example.com",
                hashed_password=default_pw,
                full_name=fake.name(),
                phone=fake.phone_number()[:20],
                bio=fake.sentence()[:150] if random.random() > 0.5 else None,
                profile_image_url=f"https://i.pravatar.cc/150?u={random.randint(1, 1000)}",
                is_premium=random.random() < 0.25,
                tuci_balance=random.randint(0, 1000),
            )
            new_users.append(user)
            users.append(user)

        if new_users:
            session.add_all(new_users)
            try:
                await session.flush()
            except Exception as e:
                print(f"❌ Kullanıcı hatası (email çakışması?): {e}")
                return

        # ── 2. LISTINGS ─────────────────────────────────────────────────────────
        print("📦 2/20: İlanlar oluşturuluyor (~2000 adet)...")
        listings: list[Listing] = []
        listings_by_cat: dict[str, list[int]] = {cat: [] for cat in CATEGORY_NAMES}

        for user in users:
            for _ in range(random.randint(10, 30)):
                cat = random.choice(CATEGORY_NAMES)
                brand_dict = random.choice(CATEGORIES[cat])
                brand = brand_dict["brand"]
                model = random.choice(brand_dict["models"])
                base_price = random.uniform(500, 50000)
                price = round(base_price + random.uniform(-0.1, 0.1) * base_price, 2)
                img_url = f"https://picsum.photos/seed/{random.randint(1, 10000)}/800/600"
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
                    image_url=img_url,
                    image_urls=json.dumps([img_url]),
                    status=ListingStatus.ACTIVE if random.random() > 0.3 else ListingStatus.PASSIVE,
                    created_at=random_date(),
                )
                listings.append(listing)

        session.add_all(listings)
        await session.flush()

        # category → listing_id eşlemesi (ClickHouse için)
        for l in listings:
            if l.category and l.status == ListingStatus.ACTIVE:
                listings_by_cat.setdefault(l.category, []).append(l.id)

        # ── 3. USER INTERESTS ────────────────────────────────────────────────────
        print("🎯 3/20: Kullanıcı ilgi alanları oluşturuluyor...")
        user_preferred_cats: dict[int, list[str]] = {}
        interests: list[UserInterest] = []
        seen_interests: set[tuple] = set()

        for user in users:
            preferred = random.sample(CATEGORY_NAMES, random.randint(2, 3))
            user_preferred_cats[user.id] = preferred
            for cat in preferred:
                key = (user.id, cat)
                if key in seen_interests:
                    continue
                seen_interests.add(key)
                interests.append(UserInterest(
                    user_id=user.id,
                    category=cat,
                    score=round(random.uniform(0.4, 1.0), 2),
                    updated_at=random_date(30),
                ))

        session.add_all(interests)
        await session.flush()

        # ── 4. FOLLOWS ──────────────────────────────────────────────────────────
        print("👥 4/20: Takip ilişkileri oluşturuluyor...")
        follows: list[Follow] = []
        seen_follows: set[tuple] = set()

        for user in users:
            targets = random.sample([u for u in users if u.id != user.id], random.randint(3, 10))
            for target in targets:
                key = (user.id, target.id)
                if key in seen_follows:
                    continue
                seen_follows.add(key)
                follows.append(Follow(
                    follower_id=user.id,
                    followed_id=target.id,
                    created_at=random_date(90),
                ))

        session.add_all(follows)
        await session.flush()

        # ── 5. FAVORITES ─────────────────────────────────────────────────────────
        print("❤️  5/20: Favoriler oluşturuluyor...")
        favorites: list[Favorite] = []
        seen_favs: set[tuple] = set()
        active_listings = [l for l in listings if l.status == ListingStatus.ACTIVE]

        for user in users:
            sample_count = min(15, len(active_listings))
            for listing in random.sample(active_listings, sample_count):
                if listing.user_id == user.id:
                    continue
                key = (user.id, listing.id)
                if key in seen_favs:
                    continue
                seen_favs.add(key)
                favorites.append(Favorite(
                    user_id=user.id,
                    listing_id=listing.id,
                    created_at=random_date(60),
                ))

        session.add_all(favorites)
        await session.flush()

        # ── 6. LISTING OFFERS ────────────────────────────────────────────────────
        print("💬 6/20: Fiyat teklifleri oluşturuluyor...")
        offers: list[ListingOffer] = []

        for user in users:
            targets = random.sample(active_listings, min(8, len(active_listings)))
            for listing in targets:
                if listing.user_id == user.id:
                    continue
                offer_price = round(listing.price * random.uniform(0.6, 0.95), 2) if listing.price else 100.0
                offers.append(ListingOffer(
                    listing_id=listing.id,
                    user_id=user.id,
                    amount=offer_price,
                    created_at=random_date(60),
                ))

        session.add_all(offers)
        await session.flush()

        # ── 7. LISTING IMPRESSIONS ───────────────────────────────────────────────
        print("👁️  7/20: İlan görüntülemeleri oluşturuluyor...")
        impressions: list[ListingImpression] = []

        for user in users:
            seen = random.sample(listings, min(50, len(listings)))
            for listing in seen:
                impressions.append(ListingImpression(
                    user_id=user.id,
                    listing_id=listing.id,
                    seen_at=recent_date(30),
                ))

        session.add_all(impressions)
        await session.flush()

        # ── 8. LIVE STREAMS ──────────────────────────────────────────────────────
        print("🎥 8/20: Canlı yayın geçmişleri oluşturuluyor...")
        streams: list[LiveStream] = []
        pro_users = [u for u in users if u.is_premium]

        for user in pro_users:
            for _ in range(random.randint(5, 20)):
                started = random_date()
                ended = started + timedelta(minutes=random.randint(15, 180))
                stream = LiveStream(
                    room_name=f"room_{user.id}_{uuid.uuid4().hex[:8]}",
                    title=fake.catch_phrase(),
                    category=random.choice(CATEGORY_NAMES),
                    host_id=user.id,
                    is_live=False,
                    viewer_count=random.randint(10, 1000),
                    started_at=started,
                    ended_at=ended,
                    thumbnail_url=f"https://picsum.photos/seed/{random.randint(1, 10000)}/800/600",
                )
                streams.append(stream)

        session.add_all(streams)
        await session.flush()

        # ── 9. STREAM VIEWERS & LIKES ────────────────────────────────────────────
        print("💫 9/20: Yayın izleyicileri ve beğenileri oluşturuluyor...")
        viewers: list[LiveStreamViewer] = []
        stream_likes: list[StreamLike] = []
        listing_likes: list[ListingLike] = []
        seen_listing_likes: set[tuple] = set()

        for stream in streams:
            audience = random.sample(users, random.randint(5, min(20, len(users))))
            for u in audience:
                viewers.append(LiveStreamViewer(
                    stream_id=stream.id,
                    user_id=u.id,
                    joined_at=stream.started_at + timedelta(minutes=random.randint(1, 10)),
                ))
                if random.random() > 0.5:
                    stream_likes.append(StreamLike(
                        stream_id=stream.id,
                        user_id=u.id,
                        created_at=stream.started_at + timedelta(minutes=random.randint(5, 15)),
                    ))

        for listing in random.sample(listings, min(500, len(listings))):
            fans = random.sample(users, random.randint(1, 10))
            for u in fans:
                key = (u.id, listing.id)
                if key in seen_listing_likes:
                    continue
                seen_listing_likes.add(key)
                listing_likes.append(ListingLike(
                    listing_id=listing.id,
                    user_id=u.id,
                    created_at=random_date(),
                ))

        session.add_all(viewers)
        session.add_all(stream_likes)
        session.add_all(listing_likes)
        await session.flush()

        # ── 10. AUCTIONS & BIDS & PURCHASES ─────────────────────────────────────
        print("⚖️  10/20: Açık artırmalar, teklifler ve satışlar oluşturuluyor...")
        auctions: list[Auction] = []

        for stream in streams:
            host_listings = [l for l in listings if l.user_id == stream.host_id]
            if not host_listings:
                continue
            for listing in random.sample(host_listings, min(random.randint(1, 5), len(host_listings))):
                start_price = (listing.price or 1000) * 0.5
                auction_end = stream.started_at + timedelta(minutes=random.randint(10, 50))
                participants = random.sample([u for u in users if u.id != stream.host_id], k=min(5, len(users) - 1))
                winner = participants[-1]
                final_price = start_price + random.randint(100, 2000)
                auctions.append(Auction(
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
                    ended_at=auction_end,
                ))

        session.add_all(auctions)
        await session.flush()

        bids: list[Bid] = []
        purchases: list[Purchase] = []

        for auction in auctions:
            if not auction.winner_id:
                continue
            bids.append(Bid(
                stream_id=auction.stream_id,
                bidder_id=auction.winner_id,
                bidder_username=auction.winner_username,
                amount=auction.final_price,
                created_at=auction.ended_at - timedelta(seconds=random.randint(1, 30)),
            ))
            target = next((l for l in listings if l.id == auction.listing_id), None)
            if target:
                target.status = ListingStatus.SOLD
                target.last_sold_price = auction.final_price
                target.last_start_price = auction.start_price
                purchases.append(Purchase(
                    listing_id=target.id,
                    buyer_id=auction.winner_id,
                    auction_id=auction.id,
                    price=auction.final_price,
                    purchase_type="AUCTION",
                    created_at=auction.ended_at,
                ))

        session.add_all(bids)
        session.add_all(purchases)
        await session.flush()

        # ── 11. STORIES ──────────────────────────────────────────────────────────
        print("📸 11/20: Hikayeler oluşturuluyor...")
        stories: list[Story] = []
        story_views: list[StoryView] = []
        story_likes_list: list[StoryLike] = []
        seen_story_likes: set[tuple] = set()

        for user in pro_users:
            for _ in range(random.randint(1, 4)):
                created = random_date(60)
                expires = created + timedelta(hours=24)
                seed_id = random.randint(1, 10000)
                story = Story(
                    user_id=user.id,
                    media_type="video",
                    video_path=f"/mock/stories/{user.id}/{uuid.uuid4().hex[:8]}.mp4",
                    video_url=f"https://picsum.photos/seed/{seed_id}/600/1000",
                    thumbnail_url=f"https://picsum.photos/seed/{seed_id}/300/500",
                    expires_at=expires,
                    created_at=created,
                )
                stories.append(story)

        session.add_all(stories)
        await session.flush()

        for story in stories:
            viewers_sample = random.sample(users, random.randint(5, 20))
            for viewer in viewers_sample:
                story_views.append(StoryView(
                    story_id=story.id,
                    viewer_id=viewer.id,
                    viewed_at=story.created_at + timedelta(minutes=random.randint(1, 60)),
                ))
                if random.random() > 0.6:
                    key = (viewer.id, story.id)
                    if key not in seen_story_likes:
                        seen_story_likes.add(key)
                        story_likes_list.append(StoryLike(
                            user_id=viewer.id,
                            story_id=story.id,
                            created_at=story.created_at + timedelta(minutes=random.randint(2, 120)),
                        ))

        session.add_all(story_views)
        session.add_all(story_likes_list)
        await session.flush()

        # ── 12. MESSAGE THREADS & DIRECT MESSAGES ───────────────────────────────
        print("💬 12/20: Mesaj konuşmaları oluşturuluyor...")
        threads: list[MessageThread] = []
        messages: list[DirectMessage] = []
        seen_threads: set[tuple] = set()

        pairs = [(users[i], users[j])
                 for i in range(len(users))
                 for j in range(i + 1, len(users))
                 if random.random() < 0.04]
        pairs = pairs[:200]

        for user_a, user_b in pairs:
            a_id, b_id = sorted([user_a.id, user_b.id])
            key = (a_id, b_id)
            if key in seen_threads:
                continue
            seen_threads.add(key)
            thread = MessageThread(
                user_a_id=a_id,
                user_b_id=b_id,
                initiator_id=user_a.id,
                status="accepted",
                created_at=random_date(90),
            )
            threads.append(thread)

        session.add_all(threads)
        await session.flush()

        listing_ids_all = [l.id for l in listings]
        for thread in threads:
            msg_count = random.randint(2, 8)
            sender, receiver = thread.user_a_id, thread.user_b_id
            for i in range(msg_count):
                s, r = (sender, receiver) if i % 2 == 0 else (receiver, sender)
                messages.append(DirectMessage(
                    sender_id=s,
                    receiver_id=r,
                    listing_id=random.choice(listing_ids_all) if random.random() > 0.6 else None,
                    content=fake.sentence(),
                    content_type="text",
                    is_read=random.random() > 0.4,
                    created_at=thread.created_at + timedelta(minutes=i * random.randint(5, 60)),
                ))

        session.add_all(messages)
        await session.flush()

        # ── 13. NOTIFICATIONS ────────────────────────────────────────────────────
        print("🔔 13/20: Bildirimler oluşturuluyor...")
        notifications: list[Notification] = []

        for user in users:
            for _ in range(random.randint(5, 15)):
                notif_type, title, body_template = random.choice(NOTIF_TYPES)
                notifications.append(Notification(
                    user_id=user.id,
                    type=notif_type,
                    title=title,
                    body=body_template,
                    is_read=random.random() > 0.5,
                    related_id=random.choice(listing_ids_all) if random.random() > 0.3 else None,
                    created_at=random_date(30),
                ))

        session.add_all(notifications)
        await session.flush()

        # ── 14. RATINGS ──────────────────────────────────────────────────────────
        print("⭐ 14/20: Değerlendirmeler oluşturuluyor...")
        ratings: list[Rating] = []
        seen_ratings: set[tuple] = set()

        for purchase in random.sample(purchases, min(150, len(purchases))):
            buyer = purchase.buyer_id
            seller_listing = next((l for l in listings if l.id == purchase.listing_id), None)
            if not seller_listing:
                continue
            seller = seller_listing.user_id
            if buyer == seller:
                continue
            key = (buyer, seller)
            if key in seen_ratings:
                continue
            seen_ratings.add(key)
            score = random.choices([5, 4, 3, 2, 1], weights=[50, 30, 10, 6, 4])[0]
            ratings.append(Rating(
                rater_id=buyer,
                rated_id=seller,
                score=score,
                comment=fake.sentence()[:200] if random.random() > 0.4 else None,
                is_read=random.random() > 0.5,
                created_at=purchase.created_at + timedelta(days=random.randint(1, 7)),
            ))

        session.add_all(ratings)
        await session.flush()

        # ── 15. TUCI TRANSACTIONS ────────────────────────────────────────────────
        print("💰 15/20: Tuci coin işlemleri oluşturuluyor...")
        transactions: list[TuciTransaction] = []
        tx_types = [
            ("purchase_reward", 50), ("bid_placed", -10), ("listing_created", 20),
            ("referral_bonus", 100), ("stream_gift_received", 30), ("daily_login", 5),
        ]

        for user in users:
            for _ in range(random.randint(3, 8)):
                tx_type, amount = random.choice(tx_types)
                ref_listing = random.choice(listing_ids_all) if random.random() > 0.5 else None
                transactions.append(TuciTransaction(
                    user_id=user.id,
                    amount=amount,
                    transaction_type=tx_type,
                    reference_id=ref_listing,
                    reference_type="listing" if ref_listing else None,
                    created_at=random_date(90),
                ))

        session.add_all(transactions)
        await session.flush()

        # ── 16. SEARCH ALERTS ────────────────────────────────────────────────────
        print("🔍 16/20: Kayıtlı aramalar oluşturuluyor...")
        search_alerts: list[SearchAlert] = []

        for user in users:
            preferred = user_preferred_cats.get(user.id, [])
            for _ in range(random.randint(1, 3)):
                cat = random.choice(preferred) if preferred else random.choice(CATEGORY_NAMES)
                queries = SEARCH_QUERIES.get(cat, ["ilan"])
                search_alerts.append(SearchAlert(
                    user_id=user.id,
                    category=cat,
                    query=random.choice(queries) if random.random() > 0.3 else None,
                    max_price=round(random.uniform(1000, 30000), 2) if random.random() > 0.5 else None,
                    status=SearchAlertStatus.ACTIVE,
                    created_at=random_date(60),
                ))

        session.add_all(search_alerts)
        await session.flush()

        # ── 17. REFERRALS ────────────────────────────────────────────────────────
        print("🔗 17/20: Referans zinciri oluşturuluyor...")
        referrals: list[Referral] = []
        seen_referrals: set[int] = set()

        shuffled = random.sample(users[1:], min(40, len(users) - 1))
        referrers = users[:10]
        for referred in shuffled:
            if referred.id in seen_referrals:
                continue
            seen_referrals.add(referred.id)
            referrer = random.choice(referrers)
            if referrer.id == referred.id:
                continue
            referrals.append(Referral(
                referrer_id=referrer.id,
                referred_id=referred.id,
                status="completed",
                created_at=random_date(120),
            ))

        session.add_all(referrals)
        await session.flush()

        # ── 18. ANALYTICS EVENTS & USER INTERACTIONS ─────────────────────────────
        print("📊 18/20: PostgreSQL analitik verileri oluşturuluyor...")
        analytics_events: list[AnalyticsEvent] = []
        user_interactions: list[UserInteraction] = []

        for user in users:
            for _ in range(random.randint(5, 15)):
                event_date = random_date()
                session_id = f"sess_{uuid.uuid4().hex[:8]}"
                analytics_events.append(AnalyticsEvent(
                    session_id=session_id,
                    user_id=user.id,
                    event_type=random.choice(["page_view", "listing_click", "stream_join", "search"]),
                    device_type=random.choice(["mobile", "desktop", "tablet"]),
                    os=random.choice(["iOS", "Android", "Windows", "macOS"]),
                    created_at=event_date,
                ))
                if listings:
                    random_listing = random.choice(listings)
                    user_interactions.append(UserInteraction(
                        user_id=user.id,
                        item_id=random_listing.id,
                        item_type="listing",
                        interaction_type=random.choice(["view", "hover", "scroll"]),
                        duration_seconds=round(random.uniform(2.0, 120.0), 1),
                        created_at=event_date,
                    ))

        session.add_all(analytics_events)
        session.add_all(user_interactions)

        # ── 19. COMMIT ───────────────────────────────────────────────────────────
        print("💾 19/20: PostgreSQL commit ediliyor...")
        await session.commit()

        pg_counts = {
            "users": len(users),
            "listings": len(listings),
            "follows": len(follows),
            "user_interests": len(interests),
            "favorites": len(favorites),
            "listing_offers": len(offers),
            "listing_impressions": len(impressions),
            "live_streams": len(streams),
            "auctions": len(auctions),
            "bids": len(bids),
            "purchases": len(purchases),
            "stories": len(stories),
            "story_views": len(story_views),
            "story_likes": len(story_likes_list),
            "message_threads": len(threads),
            "direct_messages": len(messages),
            "notifications": len(notifications),
            "ratings": len(ratings),
            "tuci_transactions": len(transactions),
            "search_alerts": len(search_alerts),
            "referrals": len(referrals),
        }
        print("  ✅ PostgreSQL:")
        for table, count in pg_counts.items():
            print(f"     {table}: {count}")

    # ── 20. CLICKHOUSE ───────────────────────────────────────────────────────────
    print("🔶 20/20: ClickHouse seed başlıyor...")
    await seed_clickhouse(users, listings_by_cat, streams, auctions, user_preferred_cats)

    print("\n✅ Tüm mock data başarıyla oluşturuldu!")


if __name__ == "__main__":
    asyncio.run(seed_data())
