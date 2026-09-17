"""
node2 AI Proxy — minimal FastAPI uygulaması.
Çalıştırma: uvicorn app.ai_proxy_main:app --host 10.10.0.3 --port 8080

Import izolasyonu: database.py / redis_client.py / LiveKit / MinIO import edilmez.
node1'deki main.py bu dosyayı import etmez; node2'de teqlif.service kurulu değildir.
"""
from contextlib import asynccontextmanager
import sentry_sdk

from fastapi import FastAPI, Header
from pydantic import BaseModel

from app.config import settings
from app.core.exceptions import ForbiddenException
from app.services.ml.llm_service import generate_listing_description, start_registry_loop


class GenerateRequest(BaseModel):
    title: str
    category: str
    condition: str | None = None
    price: float | None = None
    subcategory: str | None = None
    extra_fields: dict | None = None
    lang: str = "tr"


@asynccontextmanager
async def lifespan(app: FastAPI):
    await start_registry_loop()
    yield


# --- SENTRY ENTEGRASYONU ---
if settings.sentry_backend_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_backend_dsn,
        traces_sample_rate=0.05,
        profiles_sample_rate=0.05,
    )

app = FastAPI(lifespan=lifespan)

@app.post("/generate")
async def generate(
    body: GenerateRequest,
    x_internal_token: str = Header(...),
):
    if x_internal_token != settings.ai_proxy_internal_token:
        raise ForbiddenException()
    # generate_listing_description raises AIServiceBusyException (HTTPException 503)
    # FastAPI yakalayıp 503 döndürür; ai_proxy_client.py raise_for_status() ile fallback'e düşer.
    description, provider = await generate_listing_description(**body.model_dump())
    return {"text": description, "provider": provider}


@app.get("/health")
async def health():
    return {"status": "ok"}
