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
import app.models.state  # noqa: F401
import app.models.report  # noqa: F401
import app.models.favorite  # noqa: F401
import app.models.rating  # noqa: F401
import app.models.block  # noqa: F401
import app.models.analytics  # noqa: F401
import app.models.purchase  # noqa: F401
import app.models.story  # noqa: F401
import app.models.like  # noqa: F401
import app.models.user_interest  # noqa: F401
import app.models.listing_impression  # noqa: F401
import app.models.ad_campaign  # noqa: F401
import app.models.referral  # noqa: F401
import app.models.district  # noqa: F401
import app.models.category_field  # noqa: F401
import app.models.subcategory  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _collect_db_urls() -> list[str]:
    """Production + staging DB URL'lerini toplar (tekrarları atar)."""
    urls = [settings.database_url]

    staging_env = os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env.staging")
    if os.path.exists(staging_env):
        with open(staging_env) as f:
            for line in f:
                line = line.strip()
                if line.startswith("DATABASE_URL="):
                    staging_url = line[len("DATABASE_URL="):]
                    if staging_url and staging_url not in urls:
                        urls.append(staging_url)
                    break

    return urls


def run_migrations_offline() -> None:
    for url in _collect_db_urls():
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


async def run_async_migrations_for_url(url: str) -> None:
    cfg = dict(config.get_section(config.config_ini_section, {}))
    cfg["sqlalchemy.url"] = url
    connectable = async_engine_from_config(cfg, prefix="sqlalchemy.", poolclass=pool.NullPool)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    for url in _collect_db_urls():
        asyncio.run(run_async_migrations_for_url(url))


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
