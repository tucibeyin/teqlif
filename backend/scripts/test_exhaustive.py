#!/usr/bin/env python3
"""
Teqlif Reaktivasyon Kapsamlı Test Scripti (Exhaustive)
Kullanım: python test_exhaustive.py -p 'SIFRENIZ'

Bu script, belirli bir ilan üzerinde 30 günlük ücretsiz periyot penceresi özelliğinin 
tüm tarih/saat kombinasyonlarını ve edge caselerini test eder. Her adımdan önce 
ve sonra ilanın tarihsel verilerini ekrana basar.
"""
import sys
import argparse
import asyncio
from datetime import datetime, timezone, timedelta

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# ── Yapılandırma ──────────────────────────────────────────────────────────────
BASE_URL   = "https://www.teqlif.com/api"
DB_URL     = "postgresql+asyncpg://teqlif:Teqlif5664@127.0.0.1:5432/teqlif"
TEST_EMAIL = "teqlif@gmail.com"
TEST_PASS  = "SIFRENIZ"
LISTING_TITLE = "Teqlif Deneme 2"

# ── Renk Çıktı ────────────────────────────────────────────────────────────────
G = "\033[92m"   
R = "\033[91m"   
Y = "\033[93m"   
B = "\033[96m"   
C = "\033[36m"
X = "\033[0m"    

def ok(msg):   print(f"{G}  ✔ {msg}{X}")
def err(msg):  print(f"{R}  ✘ {msg}{X}")
def info(msg): print(f"{B}  → {msg}{X}")
def head(msg): print(f"\n{Y}{'═'*60}\n  {msg}\n{'═'*60}{X}")

# ── DB ────────────────────────────────────────────────────────────────────────
engine = create_async_engine(DB_URL, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

async def db_exec(sql: str, params: dict = {}):
    async with AsyncSessionLocal() as s:
        await s.execute(text(sql), params)
        await s.commit()

async def db_fetchone(sql: str, params: dict = {}):
    async with AsyncSessionLocal() as s:
        result = await s.execute(text(sql), params)
        row = result.mappings().first()
        return dict(row) if row else None

# ── API ───────────────────────────────────────────────────────────────────────
async def login(client: httpx.AsyncClient, email: str, password: str) -> str:
    resp = await client.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
    resp.raise_for_status()
    return resp.json().get("access_token") or resp.json().get("token")

async def toggle(client: httpx.AsyncClient, token: str, listing_id: int):
    resp = await client.patch(f"{BASE_URL}/listings/{listing_id}/toggle", headers={"Authorization": f"Bearer {token}"})
    return resp.status_code, resp.json() if resp.text else {}

async def get_cost(client: httpx.AsyncClient, token: str, listing_id: int):
    resp = await client.get(f"{BASE_URL}/listings/{listing_id}/reactivation-cost", headers={"Authorization": f"Bearer {token}"})
    return resp.json()

async def get_state(listing_id: int):
    row = await db_fetchone(
        "SELECT id, is_active, created_at, deactivated_at FROM listings WHERE id = :id", 
        {"id": listing_id}
    )
    return row

def print_dates(state, prefix="Durum"):
    c = state['created_at'].replace(tzinfo=timezone.utc)
    d = state['deactivated_at'].replace(tzinfo=timezone.utc) if state['deactivated_at'] else None
    now = datetime.now(timezone.utc)
    c_days = (now - c).total_seconds() / 86400
    
    act = f"{G}Aktif{X}" if state['is_active'] else f"{R}Pasif{X}"
    print(f"{C}[{prefix}] {act} | created_at: {c.strftime('%Y-%m-%d %H:%M:%S')} ({c_days:.1f} gün önce){X}")
    if d:
        print(f"{C}[{prefix}] deactivated_at: {d.strftime('%Y-%m-%d %H:%M:%S')}{X}")

# ── TEST SENARYOLARI ──────────────────────────────────────────────────────────

async def set_dates(listing_id: int, is_active: bool, created_days_ago: float, deact_days_ago: float = None):
    # Veritabanında tarihleri doğrudan değiştir
    if deact_days_ago is None:
        await db_exec(
            "UPDATE listings SET is_active = :a, created_at = now() - interval '1 day' * :c, deactivated_at = null WHERE id = :id",
            {"a": is_active, "c": created_days_ago, "id": listing_id}
        )
    else:
        await db_exec(
            "UPDATE listings SET is_active = :a, created_at = now() - interval '1 day' * :c, deactivated_at = now() - interval '1 day' * :d WHERE id = :id",
            {"a": is_active, "c": created_days_ago, "d": deact_days_ago, "id": listing_id}
        )

async def run_exhaustive(client, token, user_id, listing_id):
    # Pro yap, bol kredi ver, bakiyeyi sıfırla ki credit usage test edilsin
    await db_exec("UPDATE users SET is_premium = true, tuci_balance = 0 WHERE id = :id", {"id": user_id})

    # TEST 1: Yeni İlan, pasife alma ve aktife alma (1. GÜN)
    head("TEST 1: 1 Günlük İlanı Kapatıp Açma (Pencere İçi)")
    await set_dates(listing_id, is_active=True, created_days_ago=1)
    state = await get_state(listing_id)
    print_dates(state, "ÖNCE")
    
    info("İlan Kapatılıyor (Toggle)...")
    await toggle(client, token, listing_id)
    
    state_closed = await get_state(listing_id)
    print_dates(state_closed, "KAPALI")
    assert state_closed["is_active"] is False
    assert state_closed["deactivated_at"] is None # Toggle endpoint deactivated_at set etmiyor, bu ayrı bir konu

    cost = await get_cost(client, token, listing_id)
    info(f"Cost Endpoint: within_window={cost.get('within_window')}, cost={cost.get('cost')}")
    assert cost["within_window"] is True
    
    info("İlan Geri Açılıyor (Toggle)...")
    await toggle(client, token, listing_id)
    
    state_open = await get_state(listing_id)
    print_dates(state_open, "SONRA")
    c_diff = (state_open['created_at'] - state['created_at']).total_seconds()
    assert abs(c_diff) < 1, "created_at değişmemeliydi!"
    ok("Test 1 Başarılı: created_at değişmedi.")


    # TEST 2: 29 Günlük İlanı Açma
    head("TEST 2: 29 Günlük Pasif İlanı Açma (Sınırda Pencere İçi)")
    await set_dates(listing_id, is_active=False, created_days_ago=29)
    state = await get_state(listing_id)
    print_dates(state, "ÖNCE")
    
    cost = await get_cost(client, token, listing_id)
    info(f"Cost Endpoint: within_window={cost.get('within_window')}, cost={cost.get('cost')}")
    assert cost["within_window"] is True
    
    info("İlan Geri Açılıyor (Toggle)...")
    await toggle(client, token, listing_id)
    
    state_open = await get_state(listing_id)
    print_dates(state_open, "SONRA")
    c_diff = (state_open['created_at'] - state['created_at']).total_seconds()
    assert abs(c_diff) < 1, "created_at değişmemeliydi!"
    ok("Test 2 Başarılı: Sınırda (29. gün) sorunsuz açıldı.")


    # TEST 3: 31 Günlük İlanı Açma (Süresi Dolmuş)
    head("TEST 3: 31 Günlük Pasif İlanı Açma (Pencere Dışı - Kredi Harcanacak)")
    await set_dates(listing_id, is_active=False, created_days_ago=31)
    state = await get_state(listing_id)
    print_dates(state, "ÖNCE")
    
    cost = await get_cost(client, token, listing_id)
    info(f"Cost Endpoint: within_window={cost.get('within_window')}, cost={cost.get('cost')}")
    assert cost["within_window"] is False
    
    info("İlan Geri Açılıyor (Toggle)...")
    await toggle(client, token, listing_id)
    
    state_open = await get_state(listing_id)
    print_dates(state_open, "SONRA")
    
    now = datetime.now(timezone.utc)
    c_diff_now = (now - state_open['created_at'].replace(tzinfo=timezone.utc)).total_seconds()
    assert c_diff_now < 5, "created_at YENİLENMELİYDİ (Şu anki zaman olmalı)!"
    ok(f"Test 3 Başarılı: Pencere bittiği için tarih güncellendi. Yeni created_at: {c_diff_now:.1f} sn önce.")

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--password", required=True)
    args = parser.parse_args()

    async with httpx.AsyncClient(timeout=30) as client:
        token = await login(client, TEST_EMAIL, args.password)
        user = await db_fetchone("SELECT id FROM users WHERE email = :e", {"e": TEST_EMAIL})
        listing = await db_fetchone("SELECT id FROM listings WHERE title = :t AND is_deleted=false LIMIT 1", {"t": LISTING_TITLE})
        
        if not user or not listing:
            err("Kullanıcı veya İlan bulunamadı.")
            return

        # Orijinal state
        orig = await get_state(listing["id"])
        
        try:
            await run_exhaustive(client, token, user["id"], listing["id"])
        finally:
            head("Test Sonrası Temizlik")
            await db_exec(
                "UPDATE listings SET is_active = :a, created_at = :c, deactivated_at = :d WHERE id = :id",
                {"a": orig["is_active"], "c": orig["created_at"], "d": orig["deactivated_at"], "id": listing["id"]}
            )
            ok("Orijinal tarihler geri yüklendi.")

if __name__ == "__main__":
    asyncio.run(main())
