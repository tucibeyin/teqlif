#!/usr/bin/env python3
import asyncio
import getpass
import json
import urllib.request
import urllib.error
import time
import sys
import os

BASE_URL = "http://127.0.0.1:8000/api"

def api_request(method, endpoint, data=None, token=None):
    url = f"{BASE_URL}{endpoint}"
    headers = {}
    if data:
        # Check if form data or JSON based on endpoint
        if endpoint == "/auth/login":
            import urllib.parse
            data = urllib.parse.urlencode(data).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(data).encode("utf-8")
            headers["Content-Type"] = "application/json"
    
    if token:
        headers["Authorization"] = f"Bearer {token}"
        
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} on {endpoint}: {e.read().decode()}")
        return None
    except Exception as e:
        print(f"Error on {endpoint}: {e}")
        return None

def main():
    print("=== Auto-Mod DM Test Script ===")
    print("Lütfen gönderen ('teqlif') hesabı için şifreyi giriniz:")
    teqlif_pw = getpass.getpass("teqlif şifresi: ")
    
    print("\nLütfen alıcı ('tesbih') hesabı için şifreyi giriniz:")
    tesbih_pw = getpass.getpass("tesbih şifresi: ")
    
    print("\n[1] Kullanıcılara giriş yapılıyor...")
    
    # Auth login usually requires form data (grant_type, username, password) for OAuth2
    # but based on our schema UserLogin (login_identifier, password), it might accept JSON.
    # We will try JSON first since it matches UserLogin schema.
    res_teqlif = api_request("POST", "/auth/login", {"login_identifier": "teqlif", "password": teqlif_pw})
    if not res_teqlif:
        print("teqlif girişi başarısız!")
        return
    teqlif_token = res_teqlif.get("access_token")
    teqlif_id = res_teqlif["user"]["id"]
    
    res_tesbih = api_request("POST", "/auth/login", {"login_identifier": "tesbih", "password": tesbih_pw})
    if not res_tesbih:
        print("tesbih girişi başarısız!")
        return
    tesbih_token = res_tesbih.get("access_token")
    tesbih_id = res_tesbih["user"]["id"]
    
    print(f"Giriş başarılı! teqlif_id: {teqlif_id}, tesbih_id: {tesbih_id}")
    
    test_messages = [
        ("Normal kelime", "merhaba nasılsın"),
        ("False-Positive Testi (tamam)", "tamam kardeşim selam"),
        ("False-Positive Testi (klasik)", "bu çok klasik bir gün"),
        ("Yalın Küfür (am)", "am"),
        ("Yalın Küfür (yarak)", "yarak"),
        ("Kaçış Denemesi 1", "y a r a k"),
        ("Kaçış Denemesi 2", "s.i.k.t.i.r")
    ]
    
    msg_ids = []
    
    print("\n[2] Mesajlar gönderiliyor...")
    for desc, content in test_messages:
        print(f"Gönderiliyor [{desc}]: '{content}'")
        res = api_request("POST", "/messages/send", {
            "receiver_id": tesbih_id,
            "content": content
        }, token=teqlif_token)
        
        if res and "id" in res:
            msg_ids.append((desc, content, res["id"]))
            print("  -> Başarılı.")
        else:
            print("  -> BAŞARISIZ.")
        time.sleep(1) # rate limit
        
    print("\n[3] Veritabanı durumu kontrol ediliyor...")
    try:
        sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
        from app.database import async_session_maker
        from app.models.message import DirectMessage
        
        async def check_db():
            async with async_session_maker() as session:
                for desc, content, msg_id in msg_ids:
                    msg = await session.get(DirectMessage, msg_id)
                    if msg:
                        status = "BANNED (Alıcıya Gitmedi)" if msg.is_shadowbanned else "PASSED (Alıcıya Gitti)"
                        print(f"[{status}] - {desc} | '{content}'")
                    else:
                        print(f"[HATA] - Mesaj ID {msg_id} DB'de bulunamadı.")
        
        asyncio.run(check_db())
        
    except ImportError as e:
        print(f"SQLAlchemy veya Modeller yüklenemedi: {e}")
        print("Script'i backend klasöründe bir sanal ortam (venv) aktifken çalıştırdığınızdan emin olun.")

if __name__ == "__main__":
    main()
