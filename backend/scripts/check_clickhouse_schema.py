import asyncio
from app.database_clickhouse import get_clickhouse_client

async def main():
    try:
        ch = await get_clickhouse_client()
        res = await ch.query('DESCRIBE TABLE user_events')
        print("--- CLICKHOUSE user_events SCHEMA ---")
        for r in res.result_rows:
            print(r)
    except Exception as e:
        print(f"Error connecting to ClickHouse: {e}")

if __name__ == "__main__":
    asyncio.run(main())
