import asyncio
import json
import logging
import traceback
import os

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response, ORJSONResponse
from fastapi.middleware.gzip import GZipMiddleware

from app.config import settings
from app.logging_config import setup_logging
from app.core.exceptions import AppException
from app.core.error_handlers import setup_exception_handlers
from app.core.idempotency import _IdempotencyReplay
from app.routers import auth, streams, webhooks, auction, chat, moderation, stories, onboarding, direct_sale
from app.routers import search_alerts
from app.use_cases.auctions.auction_utils import pubsub_listener
from app.routers.chat import chat_pubsub_listener, moderation_pubsub_listener
from app.routers.messages import dm_pubsub_listener
from app.use_cases.direct_sales.direct_sale_scheduler import direct_sale_scheduler
from app.routers import notifications, messages, users, listings, follows, categories, upload, states, reports, favorites, search, ratings, analytics, leads, wallet
from app.security.middleware import security_headers, SecurityMiddleware
from app.security.sanitizer import InputSanitizationMiddleware
from app.security.middleware_context import LogContextMiddleware
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
from app.database import AsyncSessionLocal
from sqlalchemy import select
import app.models.auction       # noqa: F401 — tablo kaydı için
import app.models.direct_sale  # noqa: F401 — tablo kaydı için
import app.models.bid  # noqa: F401 — tablo kaydı için
import app.models.notification  # noqa: F401 — tablo kaydı için
import app.models.message  # noqa: F401 — tablo kaydı için
import app.models.listing  # noqa: F401 — tablo kaydı için
import app.models.follow  # noqa: F401 — tablo kaydı için
import app.models.category  # noqa: F401 — tablo kaydı için
import app.models.state  # noqa: F401 — tablo kaydı için
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
from app.routers import field_config
from app.routers import i18n
from app.routers import catalog
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



@asynccontextmanager
async def lifespan(app: FastAPI):
    import shutil
    from app.database import init_extensions
    from app.database_clickhouse import init_clickhouse, close_clickhouse, start_flush_loop, stop_flush_loop
    from app.core.di import init_di
    from app.services import device_service as _device_service  # noqa: F401 — TokenInvalidatedEvent handler'ını event_bus'a kaydeder

    # ffprobe kontrolü — video süre/thumbnail için gerekli
    if not shutil.which("ffprobe"):
        logger.critical(
            "[STARTUP] ffprobe bulunamadı! Video süre doğrulaması ve thumbnail oluşturma devre dışı. "
            "Düzelt: sudo apt-get install -y ffmpeg"
        )

    # i18n locale dosyalarını yükle
    from app.core.i18n import I18nService
    I18nService.load_all()

    # ARB bağımsız runtime: DB / Redis üzerinden çevirileri bellek ön belleğine yükle
    from app.utils.i18n import preload_i18n_cache
    await preload_i18n_cache()

    # DI Container'i başlat
    init_di()
    
    await init_extensions()
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
    # Schema-versioned cache — statik endpoint key builder'ları için versiyon belirleme
    from app.utils.schema_cache import init_schema_version
    await init_schema_version()
    # Kategori whitelist cache — analytics validator için startup'ta yüklenir
    from app.utils.category_cache import init_category_cache
    await init_category_cache()
    # ARQ Task Queue pool
    arq_pool = await create_pool(RedisSettings.from_dsn(settings.redis_url), default_queue_name="default")
    app.state.arq_pool = arq_pool
    set_pool(arq_pool)
    # Her worker'da Redis pub/sub dinleyicilerini başlat
    task = asyncio.create_task(pubsub_listener())
    chat_task = asyncio.create_task(chat_pubsub_listener())
    mod_task = asyncio.create_task(moderation_pubsub_listener())
    dm_task = asyncio.create_task(dm_pubsub_listener())
    ds_scheduler_task = asyncio.create_task(direct_sale_scheduler())
    # Hype Meter sönümleme döngüsü
    from app.core.hype_manager import hype_manager
    hype_manager.start_decay()
    # AI registry — node1 Groq-only (EU IP), node2 up ise Groq+Gemini iletir
    from app.services.ml.llm_service import start_registry_loop
    await start_registry_loop()
    yield
    task.cancel()
    chat_task.cancel()
    mod_task.cancel()
    dm_task.cancel()
    ds_scheduler_task.cancel()
    await asyncio.gather(task, chat_task, mod_task, dm_task, ds_scheduler_task, return_exceptions=True)
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
app.add_middleware(LogContextMiddleware)

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
app.include_router(states.router)
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
app.include_router(field_config.router)
app.include_router(i18n.router)
app.include_router(catalog.router)
app.include_router(direct_sale.router)


@app.get("/", include_in_schema=False)
async def root():
    return JSONResponse({"name": "teqlif-api", "version": "1.4"})


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
