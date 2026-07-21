from sqlalchemy import text
from sqlalchemy.pool import NullPool
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import settings

if settings.use_pgbouncer:
    engine = create_async_engine(
        settings.database_url,
        echo=False,
        poolclass=NullPool
    )
else:
    engine = create_async_engine(
        settings.database_url,
        echo=False,
        pool_size=settings.db_pool_size,
        max_overflow=settings.db_max_overflow,
        pool_timeout=settings.db_pool_timeout,
        pool_recycle=settings.db_pool_recycle
    )

AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)


class Base(DeclarativeBase):
    pass


async def init_extensions() -> None:
    """pgvector extension'ını aktifleştirir. Uygulama startup'ında bir kez çalışır.
    DB kullanıcısının superuser yetkisi yoksa sessizce geçer (extension zaten kurulu olmalı)."""
    try:
        async with engine.begin() as conn:
            await conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    except Exception:
        pass


async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def get_uow():
    """
    FastAPI Depends helper'ı — router endpoint'lerine hazır UoW enjekte eder.

    Session yaşam döngüsü get_db ile aynıdır; UoW yalnızca repository
    erişimi ve hata yönetimini sağlar. Kullanım:
        async def my_endpoint(uow: SqlAlchemyUnitOfWork = Depends(get_uow)):
    """
    from app.core.uow import SqlAlchemyUnitOfWork
    async with AsyncSessionLocal() as session:
        try:
            yield SqlAlchemyUnitOfWork.from_session(session)
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
