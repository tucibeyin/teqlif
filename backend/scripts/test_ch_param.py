import asyncio
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent))

from app.database_clickhouse import get_clickhouse_client

async def main():
    ch = await get_clickhouse_client()
    q_top = """
        SELECT lowerUTF8(trim(query)) AS normalized_query, COUNT(*) AS cnt
        FROM search_events
        WHERE timestamp >= now() - INTERVAL {days} DAY
          AND length(trim(query)) >= 2
          AND ({cat} = '' OR category = {cat})
        GROUP BY normalized_query
        HAVING cnt >= 2
        ORDER BY cnt DESC
        LIMIT 20
    """
    try:
        res = await ch.query(q_top, parameters={"days": 30, "cat": ""})
        print("Success! Data:", res.result_rows)
    except Exception as e:
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(main())
