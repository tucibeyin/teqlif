import logging
import traceback
import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse

from app.config import settings
from app.logging_config import setup_logging
from app.routers import auth, streams, webhooks

logger = setup_logging()

app = FastAPI(title="Teqlif API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://teqlif.com", "https://www.teqlif.com", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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

# Upload klasörü varsa static olarak sun
if os.path.exists(settings.upload_dir):
    app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")

# Frontend dosyalarını sun
frontend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))
if os.path.exists(frontend_dir):
    app.mount("/static", StaticFiles(directory=os.path.join(frontend_dir, "static")), name="static")

    @app.get("/", include_in_schema=False)
    async def serve_index():
        return FileResponse(os.path.join(frontend_dir, "index.html"))

    @app.get("/{page}.html", include_in_schema=False)
    async def serve_page(page: str):
        path = os.path.join(frontend_dir, f"{page}.html")
        if os.path.exists(path):
            return FileResponse(path)
        return FileResponse(os.path.join(frontend_dir, "index.html"))


@app.get("/api/health")
async def health():
    return {"status": "ok", "version": "0.1.0"}
