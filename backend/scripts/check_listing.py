import asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from datetime import datetime, timezone, timedelta
import httpx
import argparse

DB_URL = "postgresql+asyncpg://teqlif:Teqlif5664@127.0.0.1:5432/teqlif"
BASE_URL = "https://www.teqlif.com/api"
TEST_EMAIL = "teqlif@gmail.com"

engine = create_async_engine(DB_URL, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

async def check(password: str):
    async with AsyncSessionLocal() as s:
        user = (await s.execute(text("SELECT id, is_premium, tuci_balance FROM users WHERE email = :e"), {"e": TEST_EMAIL})).mappings().first()
        listing = (await s.execute(text("SELECT id, is_active, created_at FROM listings WHERE title = 'Teqlif Deneme 2' AND is_deleted=false LIMIT 1"))).mappings().first()
        
    print(f"\n--- KULLANICI DURUMU ---")
    print(f"ID: {user['id']} | PRO mu?: {user['is_premium']} | TUCi: {user['tuci_balance']}")
    
    if not listing:
        print("İlan bulunamadı!")
        return

    c = listing['created_at'].replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    c_days = (now - c).total_seconds() / 86400
    
    print(f"\n--- İLAN DURUMU ---")
    print(f"ID: {listing['id']} | Aktif mi?: {listing['is_active']}")
    print(f"Yayınlanma Tarihi (created_at): {c.strftime('%Y-%m-%d %H:%M:%S')} ({c_days:.2f} gün önce)")
    print(f"30 Günlük Pencerede mi?: {'EVET (Ücretsiz Kapat-Aç yapılabilir)' if c_days <= 30 else 'HAYIR (Süresi dolmuş, açmak ücret/kredi yer)'}")

    print("\n--- API YANITI ---")
    async with httpx.AsyncClient() as client:
        resp = await client.post(f"{BASE_URL}/auth/login", json={"email": TEST_EMAIL, "password": password})
        if resp.status_code != 200:
            print("Login hatası!", resp.text)
            return
        token = resp.json().get("access_token") or resp.json().get("token")
        
        cost_resp = await client.get(f"{BASE_URL}/listings/{listing['id']}/reactivation-cost", headers={"Authorization": f"Bearer {token}"})
        data = cost_resp.json()
        print(f"is_premium: {data.get('is_premium')}")
        print(f"free_remaining: {data.get('free_remaining')} / {data.get('free_limit')}")
        print(f"cost: {data.get('cost')} TUCi")
        print(f"can_afford: {data.get('can_afford')}")
        print(f"within_window: {data.get('within_window')}")
        
    print("\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--password", required=True)
    args = parser.parse_args()
    asyncio.run(check(args.password))
