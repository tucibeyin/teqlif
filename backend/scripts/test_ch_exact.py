import asyncio
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent))

from app.database_clickhouse import get_clickhouse_client

async def main():
    ch = await get_clickhouse_client()
    query = """
        SELECT lowerUTF8(trim(query)) AS normalized_query, COUNT(*) AS cnt
        FROM search_events
        WHERE timestamp >= now() - INTERVAL 30 DAY
          AND length(trim(query)) >= 2
        GROUP BY normalized_query
        HAVING cnt >= 2
        ORDER BY cnt DESC
        LIMIT 20
    """
    try:
        res = await ch.query(query)
        print("Success! Data:")
        for r in res.result_rows:
            print(r)
    except Exception as e:
        print("ERROR:", str(e))

if __name__ == "__main__":
    asyncio.run(main())
