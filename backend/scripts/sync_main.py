import asyncio
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sync_category_fields import sync_categories, sync_fields
from sync_locations import sync_locations


async def main() -> None:
    await sync_categories()
    await sync_fields()
    await sync_locations()


if __name__ == "__main__":
    asyncio.run(main())
