import asyncio
from app.database_clickhouse import get_clickhouse_client
async def main():
    ch = await get_clickhouse_client()
    try:
        q = "SELECT {days}"
        res = await ch.query(q, parameters={"days": 10})
        print(res.result_rows)
    except Exception as e:
        print("ERROR:", str(e))
if __name__ == "__main__":
    asyncio.run(main())
