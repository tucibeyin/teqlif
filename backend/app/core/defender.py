"""
Global Anti-Bot Defender — Aşama 1

İki katmanlı merkezi koruma:

1. AntiBotMiddleware (IP Tabanlı Global Rate Limit)
   - Her HTTP/WS isteğini Redis sliding-window sayacıyla denetler.
   - Sınırı aşan IP 10 dakika boyunca tüm endpointlerden bloke edilir.
   - IP'yi X-Forwarded-For header'ından alır (Nginx reverse proxy desteği).
   - Redis erişilemeyen durumlarda "fail-open" davranır: trafik geçer,
     hata loglanır. Böylece Redis kesintisi servisi durdurmaz.

2. Eş Zamanlı Oturum (Concurrent Session) Takibi
   - Token klonlama / bot sürüsü saldırılarına karşı sistem geneli koruma.
   - Aynı user_id ile MAX_CONCURRENT_SESSIONS'dan fazla WS bağlantısı
     açılamaz (tüm WS tipleri ortak sayaç: chat + DM + bildirim).
   - Sayaç Redis'te tutulur; bağlantı finally bloğu guarantee eder.
   - 2 saatlik TTL ile server crash sonrası zombie bağlantılar otomatik temizlenir.

Kullanım (WS endpoint'lerinde):
    from app.core.defender import (
        register_ws_session,
        release_ws_session,
        MAX_CONCURRENT_SESSIONS,
    )
    session_count = await register_ws_session(user_id)
    if session_count > MAX_CONCURRENT_SESSIONS:
        await release_ws_session(user_id)
        await websocket.close(code=4008)
        return
    try:
        ...
    finally:
        await release_ws_session(user_id)
"""

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.utils.redis_client import get_redis
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

# ── Sabitler (tüm eşikler tek yerden yönetilir) ────────────────────────────
_GLOBAL_IP_LIMIT   = 300   # Bir dakikada IP başına max istek
_GLOBAL_IP_WINDOW  = 60    # saniye — fixed-window boyutu
_IP_BLOCK_TTL      = 600   # saniye (10 dk) — limit aşılınca blok süresi

MAX_CONCURRENT_SESSIONS = 5  # Kullanıcı başına max eş zamanlı WS bağlantısı
                               # (telefon + tablet + web = 3; 2 buffer)
_SESSION_KEY_PREFIX = "sess:"
_SESSION_TTL        = 7200  # 2 saat — zombie-bağlantı güvenlik ağı

_IP_RATE_KEY_PREFIX = "ipr:"
_IP_BLOCK_KEY_PREFIX = "ipblk:"

# Bu path'ler hız sınırı dışında tutulur (health check, favicon vb.)
_BYPASS_PATHS = frozenset({"/health", "/metrics", "/favicon.ico"})


# ── Yardımcı: Gerçek IP ─────────────────────────────────────────────────────
def _get_client_ip(request: Request) -> str:
    """
    Nginx reverse proxy arkasında çalışırken gerçek istemci IP'sini döner.
    Önce X-Forwarded-For header'ına, yoksa ASGI scope'a başvurur.
    """
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "0.0.0.0"


# ── IP Rate Limit ───────────────────────────────────────────────────────────
async def _check_ip_rate_limit(ip: str) -> tuple[bool, int]:
    """
    Fixed-window IP hız limiti.
    Önce aktif blok kontrolü yapar; yoksa sayacı artırır.
    Limit aşılırsa IP_BLOCK_TTL süreliğine bloke eder.

    Returns:
        (allowed: bool, current_count: int)
        Redis hatasında fail-open → (True, 0) döner.
    """
    try:
        redis = await get_redis()

        # Önce aktif blok var mı?
        if await redis.exists(f"{_IP_BLOCK_KEY_PREFIX}{ip}"):
            return False, _GLOBAL_IP_LIMIT + 1

        # İstek sayacını artır
        rate_key = f"{_IP_RATE_KEY_PREFIX}{ip}"
        count = await redis.incr(rate_key)
        # İlk istek: pencere süresini başlat
        if count == 1:
            await redis.expire(rate_key, _GLOBAL_IP_WINDOW)

        if count > _GLOBAL_IP_LIMIT:
            # Blok anahtarını set et; rate key'i de temizle (alan israfı önlenir)
            await redis.setex(f"{_IP_BLOCK_KEY_PREFIX}{ip}", _IP_BLOCK_TTL, "1")
            await redis.delete(rate_key)
            return False, count

        return True, count

    except Exception as exc:
        # Redis erişilemiyor → fail-open: trafik geçer, hata loglanır
        logger.error(
            "[DEFENDER] Redis IP rate limit kontrolü başarısız | IP=%s | %s",
            ip, exc, exc_info=True,
        )
        return True, 0


# ── ASGI Middleware ─────────────────────────────────────────────────────────
class AntiBotMiddleware(BaseHTTPMiddleware):
    """
    Tüm HTTP ve WebSocket bağlantılarında çalışan global savunma katmanı.

    WebSocket yükseltme istekleri de (upgrade: websocket) bu middleware'den geçer;
    bot IP'leri WS handshake'e ulaşamadan HTTP 429 ile geri çevrilir.
    """

    async def dispatch(self, request: Request, call_next):
        # Bypass: sağlık kontrolleri vb.
        if request.url.path in _BYPASS_PATHS:
            return await call_next(request)

        ip = _get_client_ip(request)
        allowed, count = await _check_ip_rate_limit(ip)

        if not allowed:
            logger.warning(
                "[DEFENDER] IP engellendi | IP=%s | path=%s | count=%s",
                ip, request.url.path, count,
            )
            return JSONResponse(
                status_code=429,
                content={
                    "success": False,
                    "error": {
                        "code": "RATE_LIMIT_EXCEEDED",
                        "message": "Çok fazla istek gönderildi. Lütfen biraz bekleyin.",
                    },
                },
                headers={"Retry-After": str(_IP_BLOCK_TTL)},
            )

        return await call_next(request)


# ── Eş Zamanlı Oturum Takibi ────────────────────────────────────────────────
async def register_ws_session(user_id: int) -> int:
    """
    Yeni WS bağlantısını Redis sayacına ekler.
    TTL her çağrıda yenilenir — 2 saatlik zombie-guard aktif kalır.

    Returns:
        Kayıt sonrası güncel oturum sayısı.
        Redis hatasında fail-open → 1 döner (bağlantıya izin ver).
    """
    try:
        redis = await get_redis()
        key = f"{_SESSION_KEY_PREFIX}{user_id}"
        count = await redis.incr(key)
        await redis.expire(key, _SESSION_TTL)  # Her bağlantıda TTL yenilenir
        return int(count)
    except Exception as exc:
        logger.error(
            "[DEFENDER] register_ws_session hatası | user_id=%s | %s",
            user_id, exc, exc_info=True,
        )
        capture_exception(exc)
        return 1  # Fail-open: tek bağlantıya her zaman izin ver


async def release_ws_session(user_id: int) -> None:
    """
    WS bağlantısı kapandığında sayacı düşürür.
    Sıfır veya altına düşerse anahtarı siler (temiz state).
    WS finally bloğundan çağrılması zorunludur.
    """
    try:
        redis = await get_redis()
        key = f"{_SESSION_KEY_PREFIX}{user_id}"
        count = await redis.decr(key)
        if count <= 0:
            await redis.delete(key)
    except Exception as exc:
        logger.error(
            "[DEFENDER] release_ws_session hatası | user_id=%s | %s",
            user_id, exc, exc_info=True,
        )
        capture_exception(exc)


async def get_ws_session_count(user_id: int) -> int:
    """
    Kullanıcının o anki aktif WS oturum sayısını döner.
    Monitoring ve admin araçları için kullanılabilir.

    Returns:
        Aktif oturum sayısı. Redis hatasında 0 döner.
    """
    try:
        redis = await get_redis()
        val = await redis.get(f"{_SESSION_KEY_PREFIX}{user_id}")
        return int(val) if val else 0
    except Exception as exc:
        logger.error(
            "[DEFENDER] get_ws_session_count hatası | user_id=%s | %s",
            user_id, exc, exc_info=True,
        )
        return 0
