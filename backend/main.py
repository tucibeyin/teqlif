import asyncio
import json
import logging
import traceback
import os

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles  # frontend /static için hâlâ gerekli
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response, ORJSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.gzip import GZipMiddleware

from app.config import settings
from app.logging_config import setup_logging
from app.core.exceptions import AppException
from app.core.error_handlers import setup_exception_handlers
from app.core.idempotency import _IdempotencyReplay
from app.routers import auth, streams, webhooks, auction, chat, moderation, stories, onboarding
from app.routers import search_alerts
from app.services.auction_service import pubsub_listener
from app.routers.chat import chat_pubsub_listener, moderation_pubsub_listener
from app.routers.messages import dm_pubsub_listener
from app.routers import notifications, messages, users, listings, follows, categories, upload, cities, reports, favorites, search, ratings, analytics, leads, wallet
from app.security.middleware import security_headers, SecurityMiddleware
from app.security.sanitizer import InputSanitizationMiddleware
from app.core.rate_limit import limiter, rate_limit_exceeded_handler
from app.core.defender import AntiBotMiddleware
from slowapi.errors import RateLimitExceeded
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
import redis.asyncio as aioredis
from arq import create_pool
from arq.connections import RedisSettings
from app.core.task_queue import set_pool, clear_pool
from app.core.ws_manager import ws_manager
from app.database import engine, Base, AsyncSessionLocal
from sqlalchemy import select
from app.models.listing import Listing
from app.models.user import User
from app.models.stream import LiveStream
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
import app.models.analytics  # noqa: F401 — tablo kaydı için
import app.models.listing_offer  # noqa: F401 — tablo kaydı için
import app.models.story  # noqa: F401 — tablo kaydı için
import app.models.tuci_transaction  # noqa: F401 — tablo kaydı için
import app.models.referral  # noqa: F401 — tablo kaydı için
import app.models.like  # noqa: F401 — tablo kaydı için
import sentry_sdk
from app.routers import admin_auth
from app.routers import admin_data
from app.routers import feed
from app.routers import ads
from app.routers import client_log, config
from app.routers import calls
from prometheus_fastapi_instrumentator import Instrumentator

logger = setup_logging()

# --- SENTRY ENTEGRASYONU ---
if settings.sentry_backend_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_backend_dsn,
        traces_sample_rate=0.05,
        profiles_sample_rate=0.05,
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
    from app.database import init_extensions
    from app.database_clickhouse import init_clickhouse, close_clickhouse, start_flush_loop, stop_flush_loop
    from app.core.di import init_di
    
    # DI Container'i başlat
    init_di()
    
    await init_extensions()
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    except Exception as _create_all_exc:
        import logging
        logging.getLogger(__name__).warning(
            "create_all atlandı (alembic şemayı yönetiyor): %s", _create_all_exc
        )
    await _seed_categories()
    await _seed_cities()
    try:
        from app.services.tcmb_service import run_tcmb_job_once
        await run_tcmb_job_once()
    except Exception as e:
        logger.warning(f"TCMB startup failed: {e}")
    await init_clickhouse()
    flush_task = start_flush_loop()
    # FastAPI Cache — Redis backend (decode_responses=False: JsonCoder bytes bekler)
    _cache_redis = aioredis.from_url(settings.redis_url, decode_responses=False)
    FastAPICache.init(RedisBackend(_cache_redis), prefix="teqlif:cache")
    # ARQ Task Queue pool
    arq_pool = await create_pool(RedisSettings.from_dsn(settings.redis_url), default_queue_name="default")
    app.state.arq_pool = arq_pool
    set_pool(arq_pool)
    # Her worker'da Redis pub/sub dinleyicilerini başlat
    task = asyncio.create_task(pubsub_listener())
    chat_task = asyncio.create_task(chat_pubsub_listener())
    mod_task = asyncio.create_task(moderation_pubsub_listener())
    dm_task = asyncio.create_task(dm_pubsub_listener())
    # Hype Meter sönümleme döngüsü
    from app.core.hype_manager import hype_manager
    hype_manager.start_decay()
    yield
    task.cancel()
    chat_task.cancel()
    mod_task.cancel()
    dm_task.cancel()
    await asyncio.gather(task, chat_task, mod_task, dm_task, return_exceptions=True)
    # Tüm açık WS bağlantılarını 1001 ile kapat (graceful shutdown)
    await ws_manager.shutdown()
    hype_manager.stop_decay()
    await arq_pool.close()
    clear_pool()
    await stop_flush_loop()
    await close_clickhouse()


app = FastAPI(title="Teqlif API", version="0.1.0", lifespan=lifespan, default_response_class=ORJSONResponse)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Prometheus metrics — sadece localhost / iç ağ erişimine izin verilir
_instrumentator = Instrumentator().instrument(app)

_INTERNAL_NETS = ("127.0.0.1", "::1", "10.", "172.16.", "172.17.", "172.18.",
                  "172.19.", "172.20.", "172.21.", "172.22.", "172.23.", "172.24.",
                  "172.25.", "172.26.", "172.27.", "172.28.", "172.29.", "172.30.",
                  "172.31.", "192.168.")

@app.get("/metrics", include_in_schema=False)
async def metrics(request: Request):
    from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
    from fastapi.responses import Response
    client_ip = request.headers.get("x-forwarded-for", request.client.host if request.client else "").split(",")[0].strip()
    if not any(client_ip.startswith(prefix) for prefix in _INTERNAL_NETS):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=403, content={"detail": "Forbidden"})
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

# Security setup
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
app.middleware("http")(security_headers)


# ── Global Exception Handlers ────────────────────────────────────────────────
setup_exception_handlers(app)


app.add_middleware(AntiBotMiddleware)
app.add_middleware(InputSanitizationMiddleware)

_CORS_ORIGINS = [
    "https://teqlif.com",
    "https://admin.teqlif.com",
    "https://www.teqlif.com",
]
if settings.debug:
    _CORS_ORIGINS += ["http://localhost:3000", "http://localhost:8080"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_CORS_ORIGINS,
    allow_origin_regex=None,  # WebSocket desteği
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["Content-Type", "Authorization", "X-Requested-With"],
    expose_headers=["X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"],
)



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
app.include_router(analytics.router)
app.include_router(stories.router)
app.include_router(feed.router)
app.include_router(ads.router)
app.include_router(wallet.router)
app.include_router(leads.router)
app.include_router(client_log.router)
app.include_router(config.router)
app.include_router(onboarding.router)
app.include_router(search_alerts.router)
app.include_router(calls.router)


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


def _is_desktop_browser(request: Request) -> bool:
    """Masaüstü tarayıcı mı? Bot ve mobil cihazlar için False döner."""
    ua = request.headers.get("user-agent", "").lower()
    mobile_kw = ("android", "iphone", "ipad", "ipod", "mobile", "webos", "blackberry", "windows phone")
    bot_kw = (
        "bot", "crawl", "spider", "facebookexternalhit", "twitterbot", "whatsapp",
        "slack", "telegram", "discordbot", "linkedinbot", "pinterest", "curl", "python-requests",
    )
    return not any(kw in ua for kw in mobile_kw) and not any(kw in ua for kw in bot_kw)


if os.path.exists(frontend_dir):
    app.mount("/static", StaticFiles(directory=os.path.join(frontend_dir, "static")), name="static")

    @app.get("/", include_in_schema=False)
    async def serve_index():
        return FileResponse(os.path.join(frontend_dir, "index.html"))

    @app.get("/.well-known/apple-app-site-association", include_in_schema=False)
    async def serve_aasa():
        return FileResponse(
            os.path.join(frontend_dir, ".well-known", "apple-app-site-association"),
            media_type="application/json",
        )

    @app.get("/ilan/{listing_id}", include_in_schema=False)
    async def serve_listing_page(request: Request, listing_id: str):
        try:
            lid = int(listing_id)
        except (ValueError, TypeError):
            return HTMLResponse("<h1>404 — İlan bulunamadı</h1>", status_code=404)
        listing_id = lid
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(Listing).where(Listing.id == listing_id, Listing.status != "deleted")
            )
            listing = result.scalar_one_or_none()
        if not listing:
            return HTMLResponse(
                "<h1>404 — İlan bulunamadı</h1>", status_code=404
            )
        # Masaüstü tarayıcılar için doğrudan ilan sayfasına yönlendir
        if _is_desktop_browser(request):
            from fastapi.responses import RedirectResponse
            return RedirectResponse(url=f"/ilan.html?id={listing_id}", status_code=302)
        ctx = _listing_og(listing, listing_id)
        ctx["app_scheme"] = f"teqlif://ilan/{listing_id}"
        ctx["web_url"]    = f"/ilan.html?id={listing_id}"
        return templates.TemplateResponse(request, "app-landing.html", ctx)

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
        ctx = _user_og(user)
        ctx["app_scheme"] = f"teqlif://profil/{user.username}"
        ctx["web_url"]    = f"/profil.html?u={user.username}"
        return templates.TemplateResponse(request, "app-landing.html", ctx)



    @app.get("/mesajlar", include_in_schema=False)
    async def serve_messages_page():
        return FileResponse(os.path.join(frontend_dir, "mesajlar.html"))

    @app.get("/support", include_in_schema=False)
    async def serve_support_page():
        return FileResponse(os.path.join(frontend_dir, "support.html"))

    @app.get("/gizlilik-politikasi", include_in_schema=False)
    async def serve_privacy_page():
        return FileResponse(os.path.join(frontend_dir, "gizlilik-politikasi.html"))

    @app.get("/yayin/{stream_id}", include_in_schema=False)
    async def serve_stream_page(request: Request, stream_id: int):
        async with AsyncSessionLocal() as db:
            stream = await db.scalar(
                select(LiveStream).where(LiveStream.id == stream_id)
            )
        if not stream:
            return HTMLResponse(
                "<h1>404 — Yayın bulunamadı</h1>", status_code=404
            )
        og_image = stream.thumbnail_url or _DEFAULT_OG_IMAGE
        ctx = {
            "og_title":       f"{stream.title} — teqlif Canlı",
            "og_description": "teqlif'te canlı yayın izle ve açık artırmaya katıl.",
            "og_image":        og_image,
            "og_url":         f"https://www.teqlif.com/yayin/{stream_id}",
            "app_scheme":     f"teqlif://yayin/{stream_id}",
            "web_url":        f"/yayin.html?id={stream_id}",
        }
        return templates.TemplateResponse(request, "app-landing.html", ctx)

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


@app.get("/ads.txt", include_in_schema=False)
async def ads_txt():
    content = "google.com, pub-2403555634390058, DIRECT, f08c47fec0942fa0\n"
    return Response(content=content, media_type="text/plain")


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


@app.api_route("/.well-known/assetlinks.json", methods=["GET", "HEAD"], include_in_schema=False)
async def assetlinks():
    content = json.dumps([
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.teqlif.teqlif_mobile",
                "sha256_cert_fingerprints": [
                    "ED:0A:D6:F5:1C:E4:8B:C2:6A:2E:85:E2:20:B8:A1:24:5C:90:1A:5E:5E:69:FB:41:83:A2:39:0F:3E:DC:B0:3A"
                ]
            }
        }
    ])
    return Response(content=content, media_type="application/json")


@app.api_route("/.well-known/apple-app-site-association", methods=["GET", "HEAD"], include_in_schema=False)
async def apple_app_site_association():
    # Hem eski format (iOS 12-) hem yeni format (iOS 13+) — ikisi birlikte çalışır
    content = json.dumps({
        "applinks": {
            "details": [
                {
                    "appIDs": ["4SUTR2VZVG.teqlif"],
                    "components": [
                        { "/": "/profil/*" },
                        { "/": "/ilan/*" },
                        { "/": "/yayin/*" }
                    ]
                }
            ]
        }
    })
    return Response(content=content, media_type="application/json")


_SITEMAP_CACHE_KEY = "cache:sitemap_xml"
_SITEMAP_TTL = 3600  # 1 saat

@app.get("/sitemap.xml", include_in_schema=False)
async def sitemap_xml():
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    cached = await redis.get(_SITEMAP_CACHE_KEY)
    if cached:
        return Response(content=cached, media_type="application/xml")

    from app.models.listing import Listing
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Listing.id, Listing.created_at)
            .where(Listing.status == "active")
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
    await redis.setex(_SITEMAP_CACHE_KEY, _SITEMAP_TTL, xml)
    return Response(content=xml, media_type="application/xml")


@app.api_route("/api/health", methods=["GET", "HEAD"])
async def health():
    return {"status": "ok", "version": "0.1.0"}
