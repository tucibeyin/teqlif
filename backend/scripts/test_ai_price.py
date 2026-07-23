import asyncio
import httpx
import sys

BASE_URL = "http://127.0.0.1:8000/api"
TEST_EMAIL = "teqlif@gmail.com"

async def get_token():
    import getpass
    print(f"{TEST_EMAIL} hesabı ile test yapılacaktır.")
    password = getpass.getpass("Lütfen teqlif@gmail.com şifresini girin: ")
    
    async with httpx.AsyncClient() as client:
        # Login
        resp = await client.post(
            f"{BASE_URL}/auth/login",
            json={"email": TEST_EMAIL, "password": password}
        )
        if resp.status_code != 200:
            print(f"[HATA] Login başarısız! Yanıt: {resp.text}")
            return None
        return resp.json()["access_token"]

async def run_test(name, token, payload, expected_status=200):
    print(f"--- TEST: {name} ---")
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{BASE_URL}/analytics/price-estimate",
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
            timeout=10.0
        )
        
        if resp.status_code == expected_status:
            print(f"[BAŞARILI] {name} (HTTP {resp.status_code})")
            if resp.status_code == 200:
                data = resp.json()
                print(f"  Hızlı Satış Fiyatı: {data.get('fast_sell_price')} TUCi")
                print(f"  Piyasa Fiyatı: {data.get('market_sell_price')} TUCi")
                print(f"  Bekleyen Satış Fiyatı: {data.get('slow_sell_price')} TUCi")
                print(f"  Güven Skoru: {data.get('confidence')}")
                print(f"  Bulunan Benzer İlan: {data.get('found_similar')}")
                if data.get('alert'):
                    print(f"  [ANOMALİ]: {data.get('alert')}")
                if data.get('found_similar') == 0:
                    print("  [DİKKAT] Hiç benzer ilan bulunamadı! Veritabanında (last_sold_price > 0) olan benzer ilan yok.")
        else:
            print(f"[BAŞARISIZ] Beklenen HTTP {expected_status}, Gelen HTTP {resp.status_code}")
            print(f"  Hata Detayı: {resp.text}")
        print("")

async def main():
    token = await get_token()
    if not token:
        sys.exit(1)

    # 1. Happy Path - Elektronik
    await run_test("Normal İlan - iPhone 13", token, {
        "title": "Temiz iPhone 13 128GB",
        "description": "Kozmetik olarak çok iyi durumda, pil sağlığı %89. Sadece cihaz verilecektir.",
        "category": "electronics",
        "city": "istanbul"
    })

    # 2. Happy Path - Giyim
    await run_test("Normal İlan - Nike Ayakkabı", token, {
        "title": "Orijinal Nike Air Force 42 Numara",
        "description": "Sadece 2 kez giyildi, kutusu duruyor.",
        "category": "fashion",
        "city": "ankara"
    })

    # 3. Edge Case - Kısa Açıklama
    await run_test("Edge Case - Kısa Bilgi", token, {
        "title": "Araba",
        "description": "temiz",
        "category": "other",
        "city": "izmir"
    })

    # 4. Edge Case - Olmayan Kategori
    await run_test("Edge Case - Yanlış Kategori", token, {
        "title": "Antika Vazo",
        "description": "Osmanlı döneminden kalma",
        "category": "olmayan_kategori",
        "city": ""
    })

if __name__ == "__main__":
    asyncio.run(main())
