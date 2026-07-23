"""One-shot script: seeds districts table from zt_districts migration data."""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.config import settings
from alembic.versions.zt_districts import _DATA


async def seed():
    engine = create_async_engine(settings.database_url, echo=False)
    async with engine.begin() as conn:
        # Check if already seeded
        result = await conn.execute(text("SELECT COUNT(*) FROM districts"))
        count = result.scalar()
        if count > 0:
            print(f"Already seeded ({count} rows). Exiting.")
            return

        inserted = 0
        for province, districts in _DATA.items():
            row = await conn.execute(
                text("SELECT id FROM cities WHERE name = :name"), {"name": province}
            )
            city = row.first()
            if city is None:
                print(f"  WARNING: city not found: {province}")
                continue
            city_id = city[0]
            for district in districts:
                await conn.execute(
                    text("INSERT INTO districts (city_id, name) VALUES (:c, :n)"),
                    {"c": city_id, "n": district},
                )
                inserted += 1

        print(f"Done. Inserted {inserted} districts across {len(_DATA)} provinces.")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())
