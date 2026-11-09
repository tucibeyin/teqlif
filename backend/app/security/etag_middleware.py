import hashlib

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.logger import fire_and_forget
from app.core.read_cache import cache_store_etag, etag_normalize

_SKIP_PATHS = frozenset({"/metrics", "/sitemap.xml", "/ads.txt", "/robots.txt"})
_SKIP_PREFIXES = ("/.well-known/",)


class ETagMiddleware(BaseHTTPMiddleware):
    """GET 200 JSON yanıtlarına ETag header ekler; If-None-Match eşleşirse 304 döner.

    Yerleşim: GZipMiddleware'den içerde (add_middleware sırası olarak önce) olmalıdır;
    böylece ETag ham (sıkıştırılmamış) body üzerinden hesaplanır.
    """

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        if not self._should_process(request, response):
            return response

        body = b""
        async for chunk in response.body_iterator:
            body += chunk

        etag_hash = hashlib.md5(body, usedforsecurity=False).hexdigest()  # noqa: S324
        etag = f'"{etag_hash}"'

        # CACHE-20: Hesaplanan ETag'ı Redis etag_store'a yaz (pre-route check için).
        # Yalnızca route'un request.state'ine cache bilgisi yazdığı endpoint'lerde tetiklenir.
        cache_ns = getattr(request.state, "etag_cache_ns", None)
        if cache_ns is not None:
            fire_and_forget(
                cache_store_etag(
                    cache_ns,
                    getattr(request.state, "etag_cache_params", {}),
                    etag_hash,
                    ttl=getattr(request.state, "etag_cache_ttl", 600),
                    prefix_key=getattr(request.state, "etag_cache_prefix", None),
                ),
                tag="etag_middleware.store",
            )

        # CACHE-05: W/ zayıf ETag öneki normalize edilir (RFC 7232 §3.2).
        # Nginx gzip_vary ve Cloudflare proxy strong ETag'i W/"hash" biçimine
        # dönüştürür; normalize etmeden 304 hiçbir zaman tetiklenmez.
        # RFC 7232 §3.2: istemci virgülle ayrılmış birden fazla ETag gönderebilir.
        client_etag = request.headers.get("if-none-match", "")
        if client_etag and any(etag_normalize(p) == etag_normalize(etag) for p in client_etag.split(",")):
            return Response(status_code=304, headers={"etag": etag})

        headers = {k: v for k, v in response.headers.items() if k.lower() != "content-length"}
        headers["etag"] = etag
        return Response(
            content=body,
            status_code=response.status_code,
            headers=headers,
            media_type=response.media_type,
        )

    @staticmethod
    def _should_process(request: Request, response: Response) -> bool:
        if request.method != "GET":
            return False
        if response.status_code != 200:
            return False
        path = request.url.path
        if path in _SKIP_PATHS:
            return False
        if any(path.startswith(p) for p in _SKIP_PREFIXES):
            return False
        content_type = response.headers.get("content-type", "")
        if "application/json" not in content_type:
            return False
        # Streaming (chunked) yanıtları atla
        if response.headers.get("transfer-encoding", "").lower() == "chunked":
            return False
        return True
