import asyncio
from app.database_clickhouse import get_clickhouse_client

async def main():
    ch = await get_clickhouse_client()
    query = """
        SELECT lowerUTF8(trimBoth(query)) AS normalized_query, COUNT(*) AS cnt
        FROM search_events
        GROUP BY normalized_query
        ORDER BY cnt DESC
        LIMIT 5
    """
    try:
        res = await ch.query(query)
        print("Success:", res.result_rows)
    except Exception as e:
        print("Error:", str(e))

if __name__ == "__main__":
    asyncio.run(main())
