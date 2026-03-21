import asyncio
import json
import logging
import traceback
import os

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.templating import Jinja2Templates

from app.config import settings
from app.logging_config import setup_logging
from app.routers import auth, streams, webhooks, auction, chat, moderation
from app.routers.auction import pubsub_listener
from app.routers.chat import chat_pubsub_listener, moderation_pubsub_listener
from app.routers import notifications, messages, users, listings, follows, categories, upload, cities, reports, favorites, search, ratings
from app.security.middleware import security_headers, SecurityMiddleware, limiter, RateLimitExceeded, _rate_limit_exceeded_handler
from app.database import engine, Base, AsyncSessionLocal
from sqlalchemy import select
from app.models.listing import Listing
from app.models.user import User
import app.models.auction  # noqa: F401 — tablo kaydı için
import app.models.bid  # noqa: F401 — tablo kaydı için
import app.models.notification  # noqa: F401 — tablo kaydı için
import app.models.message  # noqa: F401 — tablo kaydı için
import app.models.listing  # noqa: F401 — tablo kaydı için
import app.models.follow  # noqa: F401 — tablo kaydı için
import app.models.category  # noqa: F401 — tablo kaydı için
import app.models.city  # noqa: F401 — tablo kaydı için
import app.models.report  # noqa: F401 — tablo kaydı için
import app.models.favorite  # noqa: F401 — tablo kaydı için
import app.models.rating  # noqa: F401 — tablo kaydı için
import app.models.block  # noqa: F401 — tablo kaydı için
import sentry_sdk
from app.routers import admin_auth
from app.routers import admin_data

logger = setup_logging()

# --- SENTRY ENTEGRASYONU ---
if settings.sentry_backend_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_backend_dsn,
        traces_sample_rate=1.0,
        profiles_sample_rate=1.0,
    )
    logger.info("Sentry Backend entegrasyonu aktif edildi.")
# ---------------------------


_SEED_CATEGORIES = [
    ("elektronik", "📱 Elektronik", 0),
    ("vasita", "🚗 Vasıta", 1),
    ("emlak", "🏠 Emlak", 2),
    ("giyim", "👗 Giyim", 3),
    ("spor", "⚽ Spor", 4),
    ("kitap", "📚 Kitap & Müzik", 5),
    ("ev", "🛋 Ev & Bahçe", 6),
    ("diger", "📦 Diğer", 7),
]


_SEED_CITIES = [
    ("Adana", 1), ("Adıyaman", 2), ("Afyonkarahisar", 3), ("Ağrı", 4),
    ("Amasya", 5), ("Ankara", 6), ("Antalya", 7), ("Artvin", 8),
    ("Aydın", 9), ("Balıkesir", 10), ("Bilecik", 11), ("Bingöl", 12),
    ("Bitlis", 13), ("Bolu", 14), ("Burdur", 15), ("Bursa", 16),
    ("Çanakkale", 17), ("Çankırı", 18), ("Çorum", 19), ("Denizli", 20),
    ("Diyarbakır", 21), ("Edirne", 22), ("Elazığ", 23), ("Erzincan", 24),
    ("Erzurum", 25), ("Eskişehir", 26), ("Gaziantep", 27), ("Giresun", 28),
    ("Gümüşhane", 29), ("Hakkari", 30), ("Hatay", 31), ("Isparta", 32),
    ("Mersin", 33), ("İstanbul", 34), ("İzmir", 35), ("Kars", 36),
    ("Kastamonu", 37), ("Kayseri", 38), ("Kırklareli", 39), ("Kırşehir", 40),
    ("Kocaeli", 41), ("Konya", 42), ("Kütahya", 43), ("Malatya", 44),
    ("Manisa", 45), ("Kahramanmaraş", 46), ("Mardin", 47), ("Muğla", 48),
    ("Muş", 49), ("Nevşehir", 50), ("Niğde", 51), ("Ordu", 52),
    ("Rize", 53), ("Sakarya", 54), ("Samsun", 55), ("Siirt", 56),
    ("Sinop", 57), ("Sivas", 58), ("Tekirdağ", 59), ("Tokat", 60),
    ("Trabzon", 61), ("Tunceli", 62), ("Şanlıurfa", 63), ("Uşak", 64),
    ("Van", 65), ("Yozgat", 66), ("Zonguldak", 67), ("Aksaray", 68),
    ("Bayburt", 69), ("Karaman", 70), ("Kırıkkale", 71), ("Batman", 72),
    ("Şırnak", 73), ("Bartın", 74), ("Ardahan", 75), ("Iğdır", 76),
    ("Yalova", 77), ("Karabük", 78), ("Kilis", 79), ("Osmaniye", 80),
    ("Düzce", 81),
]


async def _seed_categories():
    from app.models.category import Category
    async with AsyncSessionLocal() as db:
        for key, label, order in _SEED_CATEGORIES:
            existing = await db.scalar(select(Category).where(Category.key == key))
            if existing:
                existing.label = label
                existing.sort_order = order
            else:
                db.add(Category(key=key, label=label, sort_order=order))
        await db.commit()


async def _seed_cities():
    from app.models.city import City
    async with AsyncSessionLocal() as db:
        for name, order in _SEED_CITIES:
            existing = await db.scalar(select(City).where(City.name == name))
            if not existing:
                db.add(City(name=name, sort_order=order))
        await db.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await _seed_categories()
    await _seed_cities()
    # Her worker'da Redis pub/sub dinleyicilerini başlat
    task = asyncio.create_task(pubsub_listener())
    chat_task = asyncio.create_task(chat_pubsub_listener())
    mod_task = asyncio.create_task(moderation_pubsub_listener())
    yield
    task.cancel()
    chat_task.cancel()
    mod_task.cancel()
    await asyncio.gather(task, chat_task, mod_task, return_exceptions=True)


app = FastAPI(title="Teqlif API", version="0.1.0", lifespan=lifespan)

# Security setup
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.middleware("http")(security_headers)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    try:
        errors = exc.errors()
    except Exception:
        errors = str(exc)
    # ctx içindeki ValueError gibi serialize edilemeyen nesneleri string'e çevir
    def _safe(obj):
        if isinstance(obj, dict):
            return {k: _safe(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [_safe(i) for i in obj]
        if isinstance(obj, (str, int, float, bool, type(None))):
            return obj
        return str(obj)
    safe_errors = _safe(errors)
    logger.error("[422] %s %s | errors=%s", request.method, request.url.path, safe_errors)
    return JSONResponse(status_code=422, content={"detail": safe_errors})


app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://teqlif.com",
        "https://admin.teqlif.com", 
        "https://www.teqlif.com",
        "http://localhost:3000",
        "http://localhost:8080",
    ],
    allow_origin_regex=None,  # WebSocket desteği
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["Content-Type", "Authorization", "X-Requested-With"],
    expose_headers=["X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"],
)


@app.middleware("http")
async def log_errors(request: Request, call_next):
    try:
        response = await call_next(request)
        if response.status_code >= 500:
            logger.error(
                "HTTP %s %s → %s",
                request.method,
                request.url.path,
                response.status_code,
            )
        return response
    except Exception:
        logger.error(
            "Beklenmeyen hata: %s %s\n%s",
            request.method,
            request.url.path,
            traceback.format_exc(),
        )
        return JSONResponse(status_code=500, content={"detail": "Sunucu hatası"})


# Router'ları kaydet
app.include_router(auth.router)
app.include_router(streams.router)
app.include_router(webhooks.router)
app.include_router(auction.router)
app.include_router(chat.router)
app.include_router(notifications.router)
app.include_router(messages.router)
app.include_router(users.router)
app.include_router(listings.router)
app.include_router(follows.router)
app.include_router(categories.router)
app.include_router(cities.router)
app.include_router(reports.router)
app.include_router(favorites.router)
app.include_router(search.router)
app.include_router(ratings.router)
app.include_router(upload.router)
app.include_router(admin_auth.router)
app.include_router(admin_data.router)
app.include_router(moderation.router)

# Upload klasörü varsa static olarak sun
if os.path.exists(settings.upload_dir):
    app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")

# Frontend dosyalarını sun
frontend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))
templates = Jinja2Templates(directory=frontend_dir)

_DEFAULT_OG_IMAGE = "https://teqlif.com/static/icons/icon.svg"


def _listing_og(listing: Listing, listing_id: int) -> dict:
    """Listing'den OpenGraph context sözlüğü üretir."""
    urls = json.loads(listing.image_urls) if listing.image_urls else []
    og_image = urls[0] if urls else (listing.image_url or _DEFAULT_OG_IMAGE)
    price_str = f"{int(listing.price):,} ₺".replace(",", ".") if listing.price else ""
    desc_parts = [p for p in [price_str, listing.description] if p]
    og_description = " — ".join(desc_parts)[:200] if desc_parts else "teqlif'te satılık ilan"
    return {
        "og_title": listing.title,
        "og_description": og_description,
        "og_image": og_image,
        "og_url": f"https://teqlif.com/ilan/{listing_id}",
    }


def _user_og(user: User) -> dict:
    """User'dan OpenGraph context sözlüğü üretir."""
    name = user.full_name or user.username
    return {
        "og_title": f"{name} — teqlif",
        "og_description": f"{name} kullanıcısının ilanlarını ve satışlarını teqlif'te incele.",
        "og_image": user.profile_image_url or _DEFAULT_OG_IMAGE,
        "og_url": f"https://teqlif.com/profil/{user.username}",
    }


if os.path.exists(frontend_dir):
    app.mount("/static", StaticFiles(directory=os.path.join(frontend_dir, "static")), name="static")

    @app.get("/", include_in_schema=False)
    async def serve_index():
        return FileResponse(os.path.join(frontend_dir, "index.html"))

    @app.get("/ilan/{listing_id}", include_in_schema=False)
    async def serve_listing_page(request: Request, listing_id: int):
        async with AsyncSessionLocal() as db:
            listing = await db.scalar(
                select(Listing).where(Listing.id == listing_id, Listing.is_deleted.is_(False))
            )
        if not listing:
            return HTMLResponse(
                "<h1>404 — İlan bulunamadı</h1>", status_code=404
            )
        return templates.TemplateResponse(
            request, "ilan.html", _listing_og(listing, listing_id)
        )

    @app.get("/profil/{username}", include_in_schema=False)
    async def serve_profile_page(request: Request, username: str):
        async with AsyncSessionLocal() as db:
            user = await db.scalar(
                select(User).where(User.username == username, User.is_active.is_(True))
            )
        if not user:
            return HTMLResponse(
                "<h1>404 — Kullanıcı bulunamadı</h1>", status_code=404
            )
        return templates.TemplateResponse(
            request, "profil.html", _user_og(user)
        )

    @app.get("/mesajlar", include_in_schema=False)
    async def serve_messages_page():
        return FileResponse(os.path.join(frontend_dir, "mesajlar.html"))

    @app.get("/support", include_in_schema=False)
    async def serve_support_page():
        return FileResponse(os.path.join(frontend_dir, "support.html"))

    @app.get("/gizlilik-politikasi", include_in_schema=False)
    async def serve_privacy_page():
        return FileResponse(os.path.join(frontend_dir, "gizlilik-politikasi.html"))

    @app.get("/{page}.html", include_in_schema=False)
    async def serve_page(page: str):
        path = os.path.join(frontend_dir, f"{page}.html")
        if os.path.exists(path):
            return FileResponse(path)
        return FileResponse(os.path.join(frontend_dir, "index.html"))


@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    path = os.path.join(frontend_dir, "static", "icons", "favicon.ico")
    return FileResponse(path, media_type="image/x-icon")


@app.get("/robots.txt", include_in_schema=False)
async def robots_txt():
    content = (
        "User-agent: *\n"
        "Allow: /\n"
        "Disallow: /api/\n"
        "Disallow: /mesajlar\n"
        "Disallow: /mesajlar.html\n"
        "Disallow: /hesabim.html\n"
        "Disallow: /yayin.html\n"
        "Disallow: /ilan-ver.html\n\n"
        "Sitemap: https://teqlif.com/sitemap.xml\n"
    )
    return Response(content=content, media_type="text/plain")


@app.get("/sitemap.xml", include_in_schema=False)
async def sitemap_xml():
    from app.models.listing import Listing
    from app.database import get_db
    from sqlalchemy.ext.asyncio import AsyncSession
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Listing.id, Listing.created_at)
            .where(Listing.is_active.is_(True))
            .order_by(Listing.created_at.desc())
        )
        listings = result.all()

    urls = [
        "<url><loc>https://teqlif.com/</loc>"
        "<changefreq>daily</changefreq><priority>1.0</priority></url>",
    ]
    for row in listings:
        lastmod = row.created_at.strftime("%Y-%m-%d") if row.created_at else ""
        urls.append(
            f"<url><loc>https://teqlif.com/ilan/{row.id}</loc>"
            f"<lastmod>{lastmod}</lastmod>"
            "<changefreq>weekly</changefreq><priority>0.8</priority></url>"
        )

    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "\n".join(urls)
        + "\n</urlset>"
    )
    return Response(content=xml, media_type="application/xml")


@app.api_route("/api/health", methods=["GET", "HEAD"])
async def health():
    return {"status": "ok", "version": "0.1.0"}
