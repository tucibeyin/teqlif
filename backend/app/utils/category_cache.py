"""
Startup'ta categories tablosundan aktif key'leri yükler ve memory'de tutar.

Pydantic validator'ları senkron çalıştığından async DB sorgusu yapamaz.
Bu modül lifespan içinde bir kez yüklenir; sonraki tüm validasyonlar
senkron set lookup ile çalışır — ek DB/Redis maliyeti yoktur.

Yeni kategori eklenince: DB'ye kayıt → teqlif-restart → cache güncellenir.
"""
import logging

logger = logging.getLogger(__name__)

_valid_keys: frozenset[str] = frozenset()


async def init_category_cache() -> None:
    """categories tablosundan is_listable=True, status=active key'leri yükler."""
    global _valid_keys
    try:
        from app.database import async_session_maker
        from app.models.category import Category
        from sqlalchemy import select

        async with async_session_maker() as session:
            result = await session.execute(
                select(Category.key).where(
                    Category.status == "active",
                    Category.is_listable.is_(True),
                )
            )
            keys = frozenset(row[0] for row in result.all())

        _valid_keys = keys
        logger.info("[category_cache] %d aktif kategori key'i yüklendi", len(keys))
    except Exception as exc:
        logger.warning("[category_cache] Kategori key'leri yüklenemedi: %s", exc)


def get_valid_category_keys() -> frozenset[str]:
    return _valid_keys
