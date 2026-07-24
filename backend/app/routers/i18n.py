import hashlib
import json

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException
from app.database import get_db
from app.utils.redis_client import get_redis

router = APIRouter(prefix="/api/i18n", tags=["i18n"])

_SUPPORTED_LANGS = {"tr", "en", "ar", "ru"}
_CACHE_TTL = 3600  # 1 hour


def _cache_key(lang: str) -> str:
    return f"i18n:{lang}"


async def _load_pack(lang: str, db: AsyncSession) -> dict[str, str]:
    result = await db.execute(
        text("SELECT key, value FROM translations WHERE lang = :lang"),
        {"lang": lang},
    )
    return {row.key: row.value for row in result}


@router.get("/{lang}")
async def get_language_pack(
    lang: str,
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    if lang not in _SUPPORTED_LANGS:
        raise BadRequestException(code="UNSUPPORTED_LANGUAGE")

    redis = await get_redis()
    cached = await redis.get(_cache_key(lang))
    if cached:
        return json.loads(cached)

    pack = await _load_pack(lang, db)
    await redis.set(_cache_key(lang), json.dumps(pack, ensure_ascii=False), ex=_CACHE_TTL)
    return pack


@router.get("/{lang}/version")
async def get_language_version(
    lang: str,
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    if lang not in _SUPPORTED_LANGS:
        raise BadRequestException(code="UNSUPPORTED_LANGUAGE")

    redis = await get_redis()
    version_key = f"i18n:{lang}:version"
    cached_version = await redis.get(version_key)
    if cached_version:
        return {"version": cached_version}

    pack = await _load_pack(lang, db)
    digest = hashlib.md5(
        json.dumps(pack, sort_keys=True, ensure_ascii=False).encode()
    ).hexdigest()
    await redis.set(version_key, digest, ex=_CACHE_TTL)
    return {"version": digest}
