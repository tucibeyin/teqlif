import asyncio
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.schemas.user import UserOut, TokenOut

async def main():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User).where(User.email == 'teqlif@gmail.com'))
        user = res.scalar_one_or_none()
        
        out = UserOut.model_validate(user)
        print("UserOut dict:", out.model_dump())
        
        token_out = TokenOut(
            access_token="test",
            user=out
        )
        print("TokenOut JSON:", token_out.model_dump_json(indent=2))

if __name__ == "__main__":
    asyncio.run(main())
