import asyncio
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User

async def main():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User).where(User.is_premium == True))
        users = res.scalars().all()
        
        count = 0
        for user in users:
            if user.plan_type != 'monthly':
                user.plan_type = 'monthly'
                count += 1
                
        if count > 0:
            await db.commit()
            print(f"Successfully updated {count} PRO users to 'monthly' plan.")
        else:
            print("No PRO users needed updating. (They might already be on a plan or there are no PRO users)")

if __name__ == "__main__":
    asyncio.run(main())
