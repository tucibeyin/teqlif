"""
Staging ortamı için tam mock data seed scripti.
PostgreSQL: 20 tablo  |  ClickHouse: 5 tablo
Tüm data birbiriyle tutarlı — listing subcategory/fiyat/extra_fields
diğer tablolara (offers, events, favorites, searches) yansır.
"""
import asyncio
import json
import os
import sys
import random
import uuid
from datetime import datetime, timedelta, timezone
from faker import Faker

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
repo_root   = os.path.dirname(backend_dir)
sys.path.append(backend_dir)

from dotenv import load_dotenv
load_dotenv(os.environ.get("TEQLIF_ENV_FILE", ""))

from sqlalchemy import select
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

fake = Faker("tr_TR")
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── Kategori şemaları (JSON dosyalarından) ─────────────────────────────────────

_CAT_DIR = os.path.join(repo_root, "documents", "categorization")

CATEGORY_SCHEMAS: dict[str, dict[str, list]] = {}
for _fname in os.listdir(_CAT_DIR):
    if _fname.endswith(".json"):
        with open(os.path.join(_CAT_DIR, _fname), encoding="utf-8") as _f:
            _data = json.load(_f)
            CATEGORY_SCHEMAS[_data["category"]] = _data.get("subcategories", {})

SUBCATEGORY_MAP: dict[str, list[str]] = {
    cat: list(subcats.keys()) for cat, subcats in CATEGORY_SCHEMAS.items()
}

# ── Fiyat aralıkları (TL) ─────────────────────────────────────────────────────

PRICE_RANGES: dict[str, tuple[float, float]] = {
    "electronics":  (1_000,   80_000),
    "vehicles":     (50_000, 2_000_000),
    "real_estate":  (500_000, 50_000_000),
    "fashion":      (100,    15_000),
    "sports":       (200,    20_000),
    "books":        (20,     500),
    "home":         (200,    50_000),
    "other":        (500,    100_000),
}

CONDITIONS = ["Sıfır", "Yeni Gibi", "İkinci El", "Yıpranmış"]

CATEGORY_NAMES = list(CATEGORY_SCHEMAS.keys()) or [
    "electronics", "vehicles", "real_estate", "fashion",
    "sports", "books", "home", "other",
]

# ── Türkiye illeri ─────────────────────────────────────────────────────────────

PROVINCES = [
    "Adana", "Ankara", "Antalya", "Bursa", "Diyarbakır", "Eskişehir",
    "Gaziantep", "İstanbul", "İzmir", "Kayseri", "Kocaeli", "Konya",
    "Malatya", "Mersin", "Muğla", "Samsun", "Şanlıurfa", "Trabzon",
    "Van", "Zonguldak",
]

DISTRICTS: dict[str, list[str]] = {
    "İstanbul": ["Kadıköy", "Beşiktaş", "Üsküdar", "Fatih", "Şişli", "Beyoğlu",
                 "Ataşehir", "Maltepe", "Kartal", "Pendik", "Ümraniye"],
    "Ankara":   ["Çankaya", "Keçiören", "Mamak", "Altındağ", "Etimesgut", "Sincan"],
    "İzmir":    ["Konak", "Bornova", "Karşıyaka", "Buca", "Bayraklı", "Çiğli"],
    "Bursa":    ["Osmangazi", "Nilüfer", "Yıldırım", "İnegöl", "Gemlik"],
    "Antalya":  ["Muratpaşa", "Kepez", "Konyaaltı", "Alanya", "Manavgat"],
}

# ── Başlık şablonları ─────────────────────────────────────────────────────────

TITLE_TEMPLATES: dict[str, list[str]] = {
    "electronics":  ["{brand} {model}", "{brand} {model} - {condition}", "Satılık {brand} {model}",
                     "{model} ({brand}) tertemiz"],
    "vehicles":     ["{year} {brand} {model}", "{brand} {model} {year} model",
                     "{brand} {model} - {km} km", "Sahibinden {brand} {model}"],
    "real_estate":  ["{size}m² {subcat_label} - {district}/{province}",
                     "Satılık {size}m² {subcat_label}", "Kiralık {size}m² {subcat_label}"],
    "fashion":      ["{brand} {model} - {condition}", "{brand} {model}",
                     "Orjinal {brand} {model}", "{brand} {model} - {size}"],
    "sports":       ["{brand} {model}", "Satılık {brand} {model}",
                     "{brand} {model} - {condition}"],
    "books":        ["{title} - {author}", "{title}", "{title} ({genre} roman)"],
    "home":         ["{brand} {model}", "{brand} {model} - {condition}",
                     "Satılık {brand} {model}"],
    "other":        ["{brand} {model}", "Satılık {brand} {model} - {condition}",
                     "Orjinal {brand} {model}"],
}

# Kitap isimleri
BOOK_TITLES  = ["Suç ve Ceza", "Sefiller", "1984", "Hayvan Çiftliği", "Dönüşüm",
                "Simyacı", "Bülbülü Öldürmek", "İnce Memed", "Tutunamayanlar",
                "Beyaz Diş", "Martin Eden", "Uçurtma Avcısı", "Kürk Mantolu Madonna"]
BOOK_AUTHORS = ["Dostoyevski", "Victor Hugo", "George Orwell", "Franz Kafka",
                "Paulo Coelho", "Harper Lee", "Yaşar Kemal", "Oğuz Atay",
                "Jack London", "Khaled Hosseini", "Sabahattin Ali"]
BOOK_GENRES  = ["Klasik", "Distopya", "Macera", "Psikolojik", "Tarihi", "Polisiye"]

# Araç markaları
VEHICLE_BRANDS = {
    "automobile":      ["Toyota", "Honda", "Ford", "Volkswagen", "Renault",
                        "Fiat", "BMW", "Mercedes", "Audi", "Hyundai", "Kia"],
    "motorcycle":      ["Honda", "Yamaha", "Kawasaki", "Suzuki", "BMW",
                        "Ducati", "KTM", "Triumph"],
    "electric_vehicle":["Tesla", "BMW i", "Volkswagen ID", "Renault Zoe",
                        "Hyundai Ioniq", "Kia EV"],
    "truck":           ["Mercedes Actros", "Volvo FH", "Scania R", "MAN TGX"],
    "boat":            ["Bayliner", "Sea Ray", "Chaparral", "Jeanneau"],
}

VEHICLE_MODELS: dict[str, list[str]] = {
    "Toyota":      ["Corolla", "Yaris", "Camry", "RAV4", "C-HR"],
    "Honda":       ["Civic", "Jazz", "CR-V", "HR-V"],
    "Volkswagen":  ["Golf", "Passat", "Polo", "Tiguan", "T-Roc"],
    "Renault":     ["Clio", "Megane", "Kadjar", "Symbol", "Duster"],
    "BMW":         ["316i", "320i", "520d", "X3", "X5"],
    "Mercedes":    ["A180", "C200", "E220", "GLC", "Vito"],
    "Ford":        ["Focus", "Fiesta", "Kuga", "Puma", "Transit"],
    "Fiat":        ["Egea", "Panda", "500", "Doblo"],
    "Hyundai":     ["i20", "i30", "Tucson", "Santa Fe", "Elantra"],
}

# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

def random_date(start_days_ago: int = 180) -> datetime:
    start = datetime.now(timezone.utc) - timedelta(days=start_days_ago)
    return start + timedelta(seconds=random.randint(0, start_days_ago * 24 * 3600))


def recent_date(days: int = 7) -> datetime:
    start = datetime.now(timezone.utc) - timedelta(days=days)
    return start + timedelta(seconds=random.randint(0, days * 24 * 3600))


def _pick_field_value(field: dict) -> str | int | None:
    """Bir CategoryField tanımından rastgele geçerli değer üretir."""
    ftype = field.get("type", "text")
    options = [o for o in field.get("options", []) if o.get("parent_option_value") is None]
    if ftype == "dropdown" and options:
        return random.choice(options)["value"]
    if ftype == "number":
        unit = field.get("unit", "")
        if unit in ("yıl", "year"):
            return random.randint(2005, 2024)
        if unit in ("km",):
            return random.randint(0, 300_000)
        if unit in ("m²",):
            return random.randint(40, 400)
        if unit in ("oda",):
            return random.randint(1, 6)
        return random.randint(1, 999)
    return fake.word()


def gen_extra_fields(category: str, subcategory: str) -> dict:
    """category_fields tanımlarından JSONB extra_fields üretir."""
    schema = CATEGORY_SCHEMAS.get(category, {}).get(subcategory, [])
    result: dict = {}
    for field in schema:
        val = _pick_field_value(field)
        if val is not None:
            result[field["key"]] = val
    return result


def gen_listing_title(
    category: str, subcategory: str, extra: dict,
    province: str, district: str,
) -> str:
    templates = TITLE_TEMPLATES.get(category, ["{brand} {model}"])
    tpl = random.choice(templates)

    brand  = extra.get("brand",  "")
    model  = extra.get("model",  "")
    cond   = random.choice(CONDITIONS)
    year   = extra.get("year",   random.randint(2010, 2024))
    km     = extra.get("mileage", random.randint(0, 250_000))
    size   = extra.get("area",   random.randint(60, 250))

    # Araç başlığı: brand yoksa VEHICLE_BRANDS'ten çek
    if category == "vehicles" and not brand:
        vtype   = subcategory if subcategory in VEHICLE_BRANDS else "automobile"
        brand   = random.choice(VEHICLE_BRANDS.get(vtype, ["Toyota"]))
        models  = VEHICLE_MODELS.get(brand, ["Model"])
        model   = random.choice(models)

    # Kitap başlığı
    if category == "books":
        return random.choice(BOOK_TITLES) + " - " + random.choice(BOOK_AUTHORS)

    subcat_label = subcategory.replace("_", " ").title()

    return (
        tpl
        .replace("{brand}", brand or fake.company()[:15])
        .replace("{model}", model or fake.word().capitalize())
        .replace("{condition}", cond)
        .replace("{year}", str(year))
        .replace("{km}", f"{km:,}")
        .replace("{size}", str(size))
        .replace("{subcat_label}", subcat_label)
        .replace("{province}", province)
        .replace("{district}", district)
        .replace("{title}", random.choice(BOOK_TITLES))
        .replace("{author}", random.choice(BOOK_AUTHORS))
        .replace("{genre}", random.choice(BOOK_GENRES))
        .strip()
    )[:95]


def _safe_int(val, default: int) -> int:
    try:
        return int(val)
    except (TypeError, ValueError):
        return default


def gen_price(category: str, extra: dict) -> float:
    lo, hi = PRICE_RANGES.get(category, (500, 50_000))
    if category == "vehicles":
        age  = max(0, 2024 - _safe_int(extra.get("year"), 2015))
        base = random.uniform(lo, hi)
        return round(base * max(0.2, 1 - age * 0.05), 2)
    if category == "real_estate":
        area = _safe_int(extra.get("area", extra.get("size", 100)), 100)
        sqm  = random.uniform(8_000, 80_000)
        return round(area * sqm, 2)
    return round(random.uniform(lo, hi), 2)


# ── Bildirim tipleri ──────────────────────────────────────────────────────────

NOTIF_TYPES = [
    ("new_offer",       "Yeni Teklif",          "İlanınıza yeni bir teklif geldi"),
    ("offer_accepted",  "Teklif Kabul Edildi",   "Teklifiniz satıcı tarafından kabul edildi"),
    ("new_follower",    "Yeni Takipçi",           "Sizi takip etmeye başladı"),
    ("listing_liked",   "İlan Beğenildi",         "İlanınız beğenildi"),
    ("auction_won",     "Açık Artırma Kazandınız","Tebrikler! Açık artırmayı kazandınız"),
    ("stream_starting", "Yayın Başlıyor",         "Takip ettiğiniz satıcı yayına başladı"),
    ("price_drop",      "Fiyat Düştü",            "Favorilediğiniz ilanda fiyat düşüşü var"),
    ("message_received","Yeni Mesaj",             "Yeni bir mesajınız var"),
]

SEARCH_QUERIES: dict[str, list[str]] = {
    "electronics":  ["iphone", "samsung galaxy", "laptop", "macbook", "gaming laptop",
                     "playstation 5", "tablet", "akıllı saat", "kulaklık"],
    "vehicles":     ["ikinci el araba", "bmw", "mercedes", "volkswagen golf",
                     "sıfır araç", "suv", "motor satılık", "elektrikli araç"],
    "real_estate":  ["kiralık daire istanbul", "satılık 2+1", "villa satılık",
                     "arsa", "ofis kiralık", "istanbul daire"],
    "fashion":      ["nike air force", "adidas yeezy", "deri ceket", "spor ayakkabı",
                     "çanta", "saat", "kolyeler", "erkek giyim"],
    "home":         ["ikea koltuk", "buzdolabı", "çamaşır makinesi", "koltuk takımı",
                     "antika", "aydınlatma", "bahçe mobilyası"],
    "sports":       ["bisiklet", "dambıl seti", "koşu bandı", "çadır",
                     "kayak malzemesi", "tenis raketi"],
    "books":        ["roman satılık", "bilim kurgu", "klasik kitaplar",
                     "ders kitabı", "plak vinil", "çocuk kitabı"],
    "other":        ["rolex saat", "gitar satılık", "kedi köpek", "bebek arabası",
                     "fotoğraf makinesi", "drone"],
}

# ── ClickHouse seed ───────────────────────────────────────────────────────────

async def seed_clickhouse(
    users: list,
    listing_pool: list[dict],         # [{id, category, subcategory, price}]
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
        print("  ✅ ClickHouse bağlandı.")
    except Exception as e:
        print(f"  ⚠️  ClickHouse bağlanamadı, atlanıyor: {e}")
        return

    # Tabloları oluştur (ilk seed'de yoktur)
    print("  📋 ClickHouse tabloları oluşturuluyor (IF NOT EXISTS)...")
    from app.database_clickhouse import (
        _CREATE_FEED_ANALYTICS_TABLE,
        _CREATE_USER_EVENTS_TABLE,
        _CREATE_SEARCH_EVENTS_TABLE,
        _CREATE_SWIPE_LIVE_EVENTS_TABLE,
        _CREATE_DIRECT_SALE_EVENTS_TABLE,
    )
    for ddl in [
        _CREATE_FEED_ANALYTICS_TABLE,
        _CREATE_USER_EVENTS_TABLE,
        _CREATE_SEARCH_EVENTS_TABLE,
        _CREATE_SWIPE_LIVE_EVENTS_TABLE,
        _CREATE_DIRECT_SALE_EVENTS_TABLE,
    ]:
        await ch.command(ddl)
    print("  ✅ Tablolar hazır.")

    def ts(dt: datetime) -> str:
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    # listing'leri kategori bazında indexle
    pool_by_cat: dict[str, list[dict]] = {}
    for l in listing_pool:
        pool_by_cat.setdefault(l["category"], []).append(l)

    # ── feed_analytics ──────────────────────────────────────────────────────────
    print("  📊 feed_analytics dolduruluyor...")
    fa_rows: list = []
    for user in users:
        uid = user.id
        preferred = user_preferred_cats.get(uid, random.sample(CATEGORY_NAMES, 2))
        for _ in range(random.randint(30, 70)):
            cat = random.choice(preferred) if random.random() < 0.7 else random.choice(CATEGORY_NAMES)
            pool = pool_by_cat.get(cat, [])
            if not pool:
                continue
            item     = random.choice(pool)
            event    = random.choices(["impression", "click", "skip"], weights=[60, 25, 15])[0]
            dwell    = 0
            if event == "impression":
                dwell = random.choice([random.randint(4000, 15000), random.randint(200, 1500)])
            slot = random.randint(0, 20)
            fa_rows.append([
                ts(recent_date(7)), str(uid), str(item["id"]), event,
                dwell, "listing", slot, cat,
                item.get("condition", ""), item.get("subcategory", ""),
            ])

    if fa_rows:
        await ch.insert(
            "feed_analytics", fa_rows,
            column_names=["timestamp", "user_id", "listing_id", "event_type",
                          "dwell_time_ms", "content_type", "slot_index",
                          "stream_category", "listing_condition", "listing_subcategory"],
        )
        print(f"  ✅ feed_analytics: {len(fa_rows)} satır")

    # ── user_events ─────────────────────────────────────────────────────────────
    print("  📊 user_events dolduruluyor...")
    ue_rows: list = []
    for user in users:
        uid = user.id
        preferred = user_preferred_cats.get(uid, random.sample(CATEGORY_NAMES, 2))
        # detail_dwell
        for _ in range(random.randint(3, 10)):
            cat  = random.choice(preferred)
            pool = pool_by_cat.get(cat, [])
            if not pool:
                continue
            item = random.choice(pool)
            dur  = round(random.uniform(30.0, 180.0), 1)
            ue_rows.append([
                uid, item["id"], "listing", "detail_dwell",
                None, dur, "", ts(recent_date(14)), item.get("subcategory", ""),
            ])
        # bid_hesitation — fiyat gerçek listing fiyatından türetilir
        for _ in range(random.randint(1, 5)):
            cat  = random.choice(preferred)
            pool = pool_by_cat.get(cat, [])
            if not pool:
                continue
            item  = random.choice(pool)
            price = item.get("price", 1000)
            bid_p = round(price * random.uniform(0.7, 1.1), 2)
            ue_rows.append([
                uid, item["id"], "listing", "bid_hesitation",
                bid_p, None, "", ts(recent_date(14)), item.get("subcategory", ""),
            ])

    if ue_rows:
        await ch.insert(
            "user_events", ue_rows,
            column_names=["user_id", "item_id", "item_type", "event_type",
                          "price_point", "duration_seconds", "metadata",
                          "timestamp", "subcategory"],
        )
        print(f"  ✅ user_events: {len(ue_rows)} satır")

    # ── search_events ────────────────────────────────────────────────────────────
    print("  📊 search_events dolduruluyor...")
    se_rows: list = []
    for user in users:
        uid      = user.id
        preferred = user_preferred_cats.get(uid, random.sample(CATEGORY_NAMES, 2))
        for _ in range(random.randint(5, 15)):
            cat  = random.choice(preferred) if random.random() < 0.7 else random.choice(CATEGORY_NAMES)
            q    = random.choice(SEARCH_QUERIES.get(cat, ["ilan"]))
            # subcategory'ye özgü arama
            subcats = SUBCATEGORY_MAP.get(cat, [])
            subcat  = random.choice(subcats) if subcats else ""
            se_rows.append([
                ts(recent_date(30)), uid, q, cat,
                random.randint(0, 200),
                random.choice(["browse", "buy", "compare", ""]),
                subcat,
            ])

    if se_rows:
        await ch.insert(
            "search_events", se_rows,
            column_names=["timestamp", "user_id", "query", "category",
                          "result_count", "intent", "subcategory"],
        )
        print(f"  ✅ search_events: {len(se_rows)} satır")

    # ── swipe_live_events ─────────────────────────────────────────────────────────
    print("  📊 swipe_live_events dolduruluyor...")
    sle_rows: list = []
    for stream in random.sample(streams, min(50, len(streams))):
        cat  = stream.category or "other"
        pool = pool_by_cat.get(cat, [])
        if not pool:
            continue
        viewers = random.sample([u.id for u in users], random.randint(5, 20))
        for uid in viewers:
            session_id = uuid.uuid4().hex[:12]
            seen = random.randint(3, 15)
            for slot_i in range(seen):
                item  = random.choice(pool)
                event = random.choices(
                    ["impression", "click", "skip", "swipe_next"],
                    weights=[50, 20, 20, 10],
                )[0]
                dwell = random.randint(500, 8000) if event in ("impression", "click") else 0
                sle_rows.append([
                    uid, stream.id, item["id"], event, dwell,
                    cat, cat, item.get("condition", ""),
                    seen, slot_i, session_id, ts(random_date(30)),
                    item.get("subcategory", ""), item.get("subcategory", ""),
                ])

    if sle_rows:
        await ch.insert(
            "swipe_live_events", sle_rows,
            column_names=["user_id", "stream_id", "listing_id", "event_type",
                          "dwell_ms", "stream_category", "listing_category",
                          "listing_condition", "listings_seen", "slot_index",
                          "session_id", "timestamp",
                          "stream_subcategory", "listing_subcategory"],
        )
        print(f"  ✅ swipe_live_events: {len(sle_rows)} satır")

    # ── direct_sale_events ────────────────────────────────────────────────────────
    print("  📊 direct_sale_events dolduruluyor...")
    dse_rows: list = []
    listing_id_to_item = {l["id"]: l for l in listing_pool}
    for auction in random.sample(auctions, min(100, len(auctions))):
        if not auction.winner_id:
            continue
        item   = listing_id_to_item.get(auction.listing_id, {})
        cat    = item.get("category", "other")
        vcount = random.randint(10, 200)
        t1     = ts(auction.started_at or random_date(60))
        t2     = ts(auction.ended_at   or random_date(60))
        dse_rows.append([
            "sale_started", auction.id, auction.stream_id, 0,
            auction.winner_id, None, auction.listing_id, cat,
            None, None, None, None, None, vcount, None, None, t1,
        ])
        dse_rows.append([
            "purchase_completed", auction.id, auction.stream_id, 0,
            auction.winner_id, None, auction.listing_id, cat,
            1, auction.final_price, auction.final_price,
            None, None, vcount, "auction_ended", None, t2,
        ])

    if dse_rows:
        await ch.insert(
            "direct_sale_events", dse_rows,
            column_names=["event_type", "sale_id", "stream_id", "host_id", "user_id",
                          "order_id", "listing_id", "category", "quantity",
                          "unit_price", "total_price", "remaining_stock_before",
                          "remaining_stock_after", "viewer_count", "end_reason",
                          "orders_voided", "created_at"],
        )
        print(f"  ✅ direct_sale_events: {len(dse_rows)} satır")

    print("🔶 ClickHouse seed tamamlandı.")


# ── Ana seed fonksiyonu ───────────────────────────────────────────────────────

async def seed_data() -> None:
    print("🚀 Mock Data Seeding Başlıyor...")

    async with AsyncSessionLocal() as session:

        # ── 0. CUSTOM USER ─────────────────────────────────────────────────────
        print("💡 Test kullanıcı adı ve şifre:")
        custom_username = input("Username (boş → 'testuser'): ").strip() or "testuser"
        custom_password = input("Password (boş → 'Teqlif123!'): ").strip() or "Teqlif123!"

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
            print(f"  ✅ '{custom_username}' mevcut.")
            users.append(existing_user)
        else:
            uid  = uuid.uuid4().hex[:6]
            custom_user = User(
                username=custom_username,
                email=f"{custom_username}_{uid}@example.com",
                hashed_password=pwd_context.hash(custom_password),
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
            uid  = uuid.uuid4().hex[:6]
            name = fake.user_name()
            user = User(
                username=f"{name}_{uid}",
                email=f"{name}_{uid}@example.com",
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
                print(f"❌ Kullanıcı hatası: {e}")
                return

        # ── 2. LISTINGS ─────────────────────────────────────────────────────────
        print("📦 2/20: İlanlar oluşturuluyor (~2000 adet, tam parametre seti)...")
        listings: list[Listing] = []
        # ClickHouse için zengin listing pool
        listing_pool_data: list[dict] = []

        for user in users:
            for _ in range(random.randint(10, 30)):
                cat    = random.choice(CATEGORY_NAMES)
                subcats = SUBCATEGORY_MAP.get(cat, [])
                subcat = random.choice(subcats) if subcats else ""
                extra  = gen_extra_fields(cat, subcat)
                price  = gen_price(cat, extra)
                prov   = random.choice(PROVINCES)
                dist   = random.choice(DISTRICTS.get(prov, [prov]))
                cond   = random.choice(CONDITIONS)
                title  = gen_listing_title(cat, subcat, extra, prov, dist)

                img_count = random.randint(1, 4)
                imgs = [f"https://picsum.photos/seed/{random.randint(1, 99999)}/800/600"
                        for _ in range(img_count)]

                status = ListingStatus.ACTIVE if random.random() > 0.3 else ListingStatus.PASSIVE

                listing = Listing(
                    user_id=user.id,
                    title=title,
                    description=fake.text(max_nb_chars=300),
                    price=price,
                    category=cat,
                    subcategory=subcat,
                    brand=extra.get("brand", ""),
                    model_name=extra.get("model", extra.get("model_name", "")),
                    condition=cond,
                    location=f"{dist}/{prov}",
                    province=prov,
                    district=dist,
                    country_code="TR",
                    image_url=imgs[0],
                    image_urls=json.dumps(imgs),
                    extra_fields=extra if extra else None,
                    status=status,
                    created_at=random_date(),
                )
                listings.append(listing)

        session.add_all(listings)
        await session.flush()

        # Pool doldur (ClickHouse ve diğer tablolar için)
        for l in listings:
            if l.status == ListingStatus.ACTIVE:
                listing_pool_data.append({
                    "id":        l.id,
                    "category":  l.category,
                    "subcategory": l.subcategory or "",
                    "price":     l.price or 0,
                    "condition": l.condition or "",
                    "user_id":   l.user_id,
                })

        active_listings = [l for l in listings if l.status == ListingStatus.ACTIVE]

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
                subcats  = SUBCATEGORY_MAP.get(cat, [])
                subcat   = random.choice(subcats) if subcats else None
                interests.append(UserInterest(
                    user_id=user.id,
                    category=cat,
                    subcategory=subcat,
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
            for target in random.sample([u for u in users if u.id != user.id],
                                        random.randint(3, 10)):
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
        # Kullanıcının tercih ettiği kategorilerden ilanlara ağırlıklı favori
        print("❤️  5/20: Favoriler oluşturuluyor (kategori bilinçli)...")
        favorites: list[Favorite] = []
        seen_favs: set[tuple] = set()

        pool_by_cat_listings: dict[str, list[Listing]] = {}
        for l in active_listings:
            pool_by_cat_listings.setdefault(l.category, []).append(l)

        for user in users:
            preferred = user_preferred_cats.get(user.id, [])
            candidates: list[Listing] = []
            # %70 tercih edilen kategoriden
            for cat in preferred:
                pool = [l for l in pool_by_cat_listings.get(cat, []) if l.user_id != user.id]
                candidates.extend(random.sample(pool, min(8, len(pool))))
            # %30 rastgele
            other = [l for l in active_listings if l.user_id != user.id and l not in candidates]
            candidates.extend(random.sample(other, min(4, len(other))))

            for listing in random.sample(candidates, min(12, len(candidates))):
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
        # Teklif fiyatı ilanın gerçek fiyatının %60–95'i
        print("💬 6/20: Fiyat teklifleri oluşturuluyor...")
        offers: list[ListingOffer] = []
        listing_id_map = {l.id: l for l in listings}

        for user in users:
            preferred = user_preferred_cats.get(user.id, [])
            targets: list[Listing] = []
            for cat in preferred:
                pool = [l for l in pool_by_cat_listings.get(cat, []) if l.user_id != user.id]
                targets.extend(random.sample(pool, min(4, len(pool))))

            for listing in targets:
                price = listing.price or 1000
                offers.append(ListingOffer(
                    listing_id=listing.id,
                    user_id=user.id,
                    amount=round(price * random.uniform(0.6, 0.95), 2),
                    created_at=random_date(60),
                ))

        session.add_all(offers)
        await session.flush()

        # ── 7. LISTING IMPRESSIONS ───────────────────────────────────────────────
        print("👁️  7/20: İlan görüntülemeleri oluşturuluyor...")
        impressions: list[ListingImpression] = []

        for user in users:
            for listing in random.sample(listings, min(50, len(listings))):
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
            # Pro kullanıcının en çok hangi kategoride ilanı var?
            user_cats = [l.category for l in listings if l.user_id == user.id and l.category]
            dominant_cat = max(set(user_cats), key=user_cats.count) if user_cats else random.choice(CATEGORY_NAMES)
            for _ in range(random.randint(5, 20)):
                started = random_date()
                ended   = started + timedelta(minutes=random.randint(15, 180))
                streams.append(LiveStream(
                    room_name=f"room_{user.id}_{uuid.uuid4().hex[:8]}",
                    title=fake.catch_phrase(),
                    category=dominant_cat,
                    host_id=user.id,
                    is_live=False,
                    viewer_count=random.randint(10, 1000),
                    started_at=started,
                    ended_at=ended,
                    thumbnail_url=f"https://picsum.photos/seed/{random.randint(1, 10000)}/800/600",
                ))

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
            for u in random.sample(users, random.randint(1, 10)):
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

        # ── 10. AUCTIONS, BIDS, PURCHASES ────────────────────────────────────────
        print("⚖️  10/20: Açık artırmalar oluşturuluyor...")
        auctions: list[Auction] = []

        for stream in streams:
            host_listings = [l for l in listings if l.user_id == stream.host_id]
            if not host_listings:
                continue
            for listing in random.sample(host_listings, min(random.randint(1, 5), len(host_listings))):
                start_price = (listing.price or 1000) * 0.5
                auction_end = stream.started_at + timedelta(minutes=random.randint(10, 50))
                participants = random.sample(
                    [u for u in users if u.id != stream.host_id],
                    k=min(5, len(users) - 1),
                )
                winner      = participants[-1]
                final_price = start_price + random.randint(100, max(101, int(start_price * 0.3)))
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
            target = listing_id_map.get(auction.listing_id)
            if target:
                target.status          = ListingStatus.SOLD
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
                seed_id = random.randint(1, 10000)
                stories.append(Story(
                    user_id=user.id,
                    media_type="video",
                    video_path=f"/mock/stories/{user.id}/{uuid.uuid4().hex[:8]}.mp4",
                    video_url=f"https://picsum.photos/seed/{seed_id}/600/1000",
                    thumbnail_url=f"https://picsum.photos/seed/{seed_id}/300/500",
                    expires_at=created + timedelta(hours=24),
                    created_at=created,
                ))

        session.add_all(stories)
        await session.flush()

        for story in stories:
            for viewer in random.sample(users, random.randint(5, 20)):
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
        # Mesajlar genellikle ilan üzerinden — aynı kategori ilanlarının alıcı/satıcıları
        print("💬 12/20: Mesaj konuşmaları oluşturuluyor...")
        threads: list[MessageThread] = []
        messages: list[DirectMessage] = []
        seen_threads: set[tuple] = set()

        pairs = [(users[i], users[j])
                 for i in range(len(users))
                 for j in range(i + 1, len(users))
                 if random.random() < 0.04][:200]

        for ua, ub in pairs:
            a_id, b_id = sorted([ua.id, ub.id])
            if (a_id, b_id) in seen_threads:
                continue
            seen_threads.add((a_id, b_id))
            threads.append(MessageThread(
                user_a_id=a_id, user_b_id=b_id,
                initiator_id=ua.id, status="accepted",
                created_at=random_date(90),
            ))

        session.add_all(threads)
        await session.flush()

        listing_ids_all = [l.id for l in listings]
        for thread in threads:
            sender, receiver = thread.user_a_id, thread.user_b_id
            # İlgili ilan: sender'ın ilanlarından biri
            sender_listings = [l.id for l in listings if l.user_id == sender]
            related = random.choice(sender_listings) if sender_listings else None
            for i in range(random.randint(2, 8)):
                s, r = (sender, receiver) if i % 2 == 0 else (receiver, sender)
                messages.append(DirectMessage(
                    sender_id=s, receiver_id=r,
                    listing_id=related if i == 0 else None,
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
            user_listing_ids = [l.id for l in listings if l.user_id == user.id]
            for _ in range(random.randint(5, 15)):
                ntype, title, body = random.choice(NOTIF_TYPES)
                rel_id = (
                    random.choice(user_listing_ids) if user_listing_ids and random.random() > 0.3
                    else None
                )
                notifications.append(Notification(
                    user_id=user.id,
                    type=ntype,
                    title=title,
                    body=body,
                    is_read=random.random() > 0.5,
                    related_id=rel_id,
                    created_at=random_date(30),
                ))

        session.add_all(notifications)
        await session.flush()

        # ── 14. RATINGS ──────────────────────────────────────────────────────────
        print("⭐ 14/20: Değerlendirmeler oluşturuluyor...")
        ratings: list[Rating] = []
        seen_ratings: set[tuple] = set()

        for purchase in random.sample(purchases, min(150, len(purchases))):
            buyer  = purchase.buyer_id
            src    = listing_id_map.get(purchase.listing_id)
            if not src:
                continue
            seller = src.user_id
            if buyer == seller:
                continue
            key = (buyer, seller)
            if key in seen_ratings:
                continue
            seen_ratings.add(key)
            score = random.choices([5, 4, 3, 2, 1], weights=[50, 30, 10, 6, 4])[0]
            ratings.append(Rating(
                rater_id=buyer, rated_id=seller,
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
            user_listing_ids = [l.id for l in listings if l.user_id == user.id]
            for _ in range(random.randint(3, 8)):
                tx_type, amount = random.choice(tx_types)
                ref_id = random.choice(user_listing_ids) if user_listing_ids and random.random() > 0.5 else None
                transactions.append(TuciTransaction(
                    user_id=user.id,
                    amount=amount,
                    transaction_type=tx_type,
                    reference_id=ref_id,
                    reference_type="listing" if ref_id else None,
                    created_at=random_date(90),
                ))

        session.add_all(transactions)
        await session.flush()

        # ── 16. SEARCH ALERTS ────────────────────────────────────────────────────
        # Alert'ler kullanıcının tercih kategorilerine ve gerçek subcategory'lere dayalı
        print("🔍 16/20: Kayıtlı aramalar oluşturuluyor...")
        search_alerts: list[SearchAlert] = []

        for user in users:
            preferred = user_preferred_cats.get(user.id, [])
            for _ in range(random.randint(1, 3)):
                cat     = random.choice(preferred) if preferred else random.choice(CATEGORY_NAMES)
                queries = SEARCH_QUERIES.get(cat, ["ilan"])
                lo, hi  = PRICE_RANGES.get(cat, (500, 50_000))
                search_alerts.append(SearchAlert(
                    user_id=user.id,
                    category=cat,
                    query=random.choice(queries) if random.random() > 0.3 else None,
                    max_price=round(random.uniform(lo * 0.3, hi * 0.7), 2) if random.random() > 0.5 else None,
                    status=SearchAlertStatus.ACTIVE,
                    created_at=random_date(60),
                ))

        session.add_all(search_alerts)
        await session.flush()

        # ── 17. REFERRALS ────────────────────────────────────────────────────────
        print("🔗 17/20: Referans zinciri oluşturuluyor...")
        referrals: list[Referral] = []
        seen_referred: set[int] = set()

        for referred in random.sample(users[1:], min(40, len(users) - 1)):
            if referred.id in seen_referred:
                continue
            seen_referred.add(referred.id)
            referrer = random.choice(users[:10])
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

        # ── 18. ANALYTICS ────────────────────────────────────────────────────────
        print("📊 18/20: PostgreSQL analitik verileri oluşturuluyor...")
        analytics_events: list[AnalyticsEvent] = []
        user_interactions: list[UserInteraction] = []

        for user in users:
            preferred = user_preferred_cats.get(user.id, [])
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
                # interaction: tercih edilen kategoriden ilan
                cat  = random.choice(preferred) if preferred else random.choice(CATEGORY_NAMES)
                pool = pool_by_cat_listings.get(cat, listings)
                if pool:
                    tgt = random.choice(pool)
                    user_interactions.append(UserInteraction(
                        user_id=user.id,
                        item_id=tgt.id,
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

        print("  ✅ PostgreSQL:")
        for name, obj in [
            ("users", users), ("listings", listings), ("follows", follows),
            ("user_interests", interests), ("favorites", favorites),
            ("listing_offers", offers), ("listing_impressions", impressions),
            ("live_streams", streams), ("auctions", auctions),
            ("bids", bids), ("purchases", purchases),
            ("stories", stories), ("story_views", story_views),
            ("story_likes", story_likes_list), ("message_threads", threads),
            ("direct_messages", messages), ("notifications", notifications),
            ("ratings", ratings), ("tuci_transactions", transactions),
            ("search_alerts", search_alerts), ("referrals", referrals),
        ]:
            print(f"     {name}: {len(obj)}")

    # ── 20. CLICKHOUSE ────────────────────────────────────────────────────────────
    print("🔶 20/20: ClickHouse seed başlıyor...")
    await seed_clickhouse(users, listing_pool_data, streams, auctions, user_preferred_cats)
    print("\n✅ Tüm mock data başarıyla oluşturuldu!")


if __name__ == "__main__":
    asyncio.run(seed_data())
