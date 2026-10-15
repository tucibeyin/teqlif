import asyncio
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sync_category_fields import sync_categories, sync_subcategories, sync_fields
from sync_locations import sync_locations
from sync_translations import sync as sync_translations
from sync_feed_cache import warm_feed_cache


async def main() -> None:
    await sync_categories()
    await sync_subcategories()
    await sync_fields()
    await sync_locations()
    await sync_translations()
    await warm_feed_cache()


if __name__ == "__main__":
    asyncio.run(main())
