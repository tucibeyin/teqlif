import hashlib

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

_SKIP_PATHS = frozenset({"/metrics", "/sitemap.xml", "/ads.txt", "/robots.txt"})
_SKIP_PREFIXES = ("/.well-known/",)


def _etag_value(tag: str | None) -> str:
    """ETag veya If-None-Match değerinden W/ öneki ve tırnakları soyar.

    RFC 7232 §3.2: koşullu GET'te weak/strong karşılaştırması için hash değeri yeterli.
    Nginx (gzip_vary) ve Cloudflare proxy katmanı strong ETag'i W/ ile zayıflatır;
    bu normalize edici olmadan 304 asla tetiklenmez.
    """
    if not tag:
        return ""
    tag = tag.strip()
    if tag.startswith("W/"):
        tag = tag[2:]
    return tag.strip('"')


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

        etag = f'"{hashlib.md5(body, usedforsecurity=False).hexdigest()}"'  # noqa: S324

        # CACHE-05: W/ zayıf ETag öneki normalize edilir (RFC 7232 §3.2).
        # Nginx gzip_vary ve Cloudflare proxy strong ETag'i W/"hash" biçimine
        # dönüştürür; normalize etmeden 304 hiçbir zaman tetiklenmez.
        if _etag_value(request.headers.get("if-none-match")) == _etag_value(etag):
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
