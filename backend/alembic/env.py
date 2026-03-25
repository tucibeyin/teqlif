import asyncio
import os
import sys
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

# Proje kök dizinini path'e ekle
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.config import settings
from app.database import Base
# Tüm modeller metadata'ya kaydedilmeli — FK referansları için zorunlu
import app.models.user  # noqa: F401
import app.models.stream  # noqa: F401
import app.models.listing  # noqa: F401
import app.models.listing_offer  # noqa: F401
import app.models.auction  # noqa: F401
import app.models.bid  # noqa: F401
import app.models.notification  # noqa: F401
import app.models.message  # noqa: F401
import app.models.follow  # noqa: F401
import app.models.category  # noqa: F401
import app.models.city  # noqa: F401
import app.models.report  # noqa: F401
import app.models.favorite  # noqa: F401
import app.models.rating  # noqa: F401
import app.models.block  # noqa: F401
import app.models.analytics  # noqa: F401

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
