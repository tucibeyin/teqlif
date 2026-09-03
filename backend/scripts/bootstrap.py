"""
Sıfırdan DB kurulumu için kullanılır.
Yalnızca geliştirici/CI ortamında, boş bir DB'de çalıştırılır.
Production VPS'te bu script çalıştırılmaz — orada her zaman `alembic upgrade head` kullanılır.
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import app.models  # noqa: tüm modelleri Base.metadata'ya yükle
from alembic import command
from alembic.config import Config
from app.database import Base, engine


async def _create_tables() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


def _stamp_head() -> None:
    cfg = Config(os.path.join(os.path.dirname(__file__), '..', 'alembic.ini'))
    command.stamp(cfg, 'head')


async def bootstrap() -> None:
    print("[bootstrap] Tablolar oluşturuluyor...")
    await _create_tables()
    print("[bootstrap] Alembic head olarak işaretleniyor...")
    _stamp_head()
    print("[bootstrap] Seed verisi yükleniyor...")
    from sync_main import main as sync_main
    await sync_main()
    print("[bootstrap] Tamamlandı.")


if __name__ == "__main__":
    asyncio.run(bootstrap())
