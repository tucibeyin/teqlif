#!/var/www/teqlif.com/venv/bin/python3
"""
Sesli arama özelliği test scripti.
VPS'te backend venv ile çalışır — ek paket gerektirmez.

Çalıştırma (VPS'te):
    cd /var/www/teqlif.com
    venv/bin/python3 test_call.py

3 mod:
  1  Script telefonu arar       (2gbrain → teqlif)
  2  Telefon scripti arar       (teqlif → 2gbrain, manuel kabul/red)
  3  Telefon arar, oto-kabul    (teqlif → 2gbrain, Enter beklenmez)
"""

import asyncio
import json
import sys
import threading
import time

try:
    import httpx
    import websockets
except ImportError:
    print("Eksik: httpx veya websockets — backend venv ile çalıştır:")
    print("  ./backend/.venv/bin/python3 test_call.py")
    sys.exit(1)

# ─── Config ───────────────────────────────────────────────────────────────────
# VPS'te direkt uvicorn'a bağlanır (nginx SSL yükü olmadan)

BASE = "http://127.0.0.1:8000/api"
WS   = "ws://127.0.0.1:8000/api/messages/ws"

# ─── HTTP ─────────────────────────────────────────────────────────────────────

def login(identifier: str, password: str) -> tuple[str, int, str]:
    r = httpx.post(f"{BASE}/auth/login",
                   json={"login_identifier": identifier, "password": password},
                   timeout=10)
    r.raise_for_status()
    d = r.json()
    return d["access_token"], d["user"]["id"], d["user"]["username"]


def api(method: str, path: str, token: str, **kwargs):
    h = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    r = httpx.request(method, f"{BASE}{path}", headers=h, timeout=10, **kwargs)
    try:
        r.raise_for_status()
    except httpx.HTTPStatusError as e:
        print(f"API Error {r.status_code}: {r.text}")
        raise e
    return r.json()


def lookup_user(username: str, token: str) -> int | None:
    try:
        return api("GET", f"/users/{username}", token)["id"]
    except Exception:
        return None

# ─── Mod 1: Script → Telefon ─────────────────────────────────────────────────

async def caller_mode(token: str, me: str, callee_id: int, callee: str):
    print(f"\n📞  @{me} → @{callee} arıyor...")

    d = api("POST", "/calls/start", token, json={"callee_id": callee_id})
    call_id   = d["call_id"]
    room_name = d["room_name"]

    print(f"✅  call_id={call_id}  room={room_name}")
    print(f"📱  Telefonunuzda gelen arama ekranı açılmalı.")
    print(f"    Yeşil butona basın — 30 sn içinde cevap gelmezse missed.\n")

    t0 = time.time()
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"token": token}))
        print("🔌  WS bağlandı\n")

        while True:
            elapsed = time.time() - t0
            if elapsed > 33:
                print("\n⏰  Süre doldu — missed gönderiliyor")
                try:
                    api("POST", f"/calls/{call_id}/missed", token)
                except Exception:
                    pass
                return

            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=1.0)
            except asyncio.TimeoutError:
                print(f"\r   ⏳  {int(30 - elapsed)}s", end="", flush=True)
                continue

            msg = json.loads(raw)
            t   = msg.get("type", "")
            
            print(f"\n[WS LOG] {msg}")

            if t == "call_accepted":
                print("✅  KABUL EDİLDİ!")
                await _in_call(call_id, token, room_name, ws)
                return
            elif t in ("call_rejected",):
                print("❌  Reddedildi.")
                return
            elif t == "call_ended":
                print("🔴  Karşı taraf kapattı.")
                return

# ─── Mod 2/3: Telefon → Script ────────────────────────────────────────────────

async def callee_mode(token: str, me: str, auto: bool):
    print(f"\n👂  @{me} gelen aramayı bekliyor...")
    print(f"    Telefonda @{me}'e DM veya profil → Ara ikonuna basın.")
    if not auto:
        print("    Enter=Kabul  r+Enter=Reddet\n")
    else:
        print("    Otomatik kabul aktif\n")

    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"token": token}))
        print("🔌  WS bağlandı — bekleniyor...\n")

        while True:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
            except asyncio.TimeoutError:
                continue

            msg = json.loads(raw)
            t   = msg.get("type", "")

            print(f"\n[WS LOG] {msg}")

            if t not in ("call_incoming", "incoming_call"):
                continue

            call_id = (msg.get("call_id")
                       or msg.get("data", {}).get("call_id"))
            caller  = (msg.get("caller_username")
                       or msg.get("data", {}).get("caller_username", "?"))
            print(f"📞  GELEN ARAMA: @{caller}  (call_id={call_id})")

            if auto:
                dec = "k"
            else:
                dec = input("   [Enter]=Kabul  [r+Enter]=Reddet > ").strip().lower()

            if dec == "r":
                api("POST", f"/calls/{call_id}/reject", token)
                print("   Reddedildi.")
                return

            r = api("POST", f"/calls/{call_id}/accept", token)
            print(f"✅  Kabul!  room={r.get('room_name')}")
            await _in_call(call_id, token, r.get("room_name", ""), ws)
            return

# ─── Aktif görüşme ────────────────────────────────────────────────────────────

async def _in_call(call_id: int, token: str, room: str, ws: websockets.WebSocketClientProtocol):
    print(f"\n🟢  Görüşme aktif — room={room}")
    print(f"    Enter'a basınca görüşmeyi bitirir.\n")

    done = asyncio.Event()
    loop = asyncio.get_event_loop()

    def _wait():
        input()
        loop.call_soon_threadsafe(done.set)

    threading.Thread(target=_wait, daemon=True).start()

    t0 = time.time()
    
    recv_task = asyncio.create_task(ws.recv())
    done_task = asyncio.create_task(done.wait())
    
    while not done.is_set():
        m, s = divmod(int(time.time() - t0), 60)
        print(f"\r   📞  {m:02d}:{s:02d}  [Enter]=bitir", end="", flush=True)
        
        try:
            done_or_recv, pending = await asyncio.wait(
                [done_task, recv_task],
                timeout=1.0,
                return_when=asyncio.FIRST_COMPLETED
            )
            
            if recv_task in done_or_recv:
                try:
                    res = recv_task.result()
                    msg = json.loads(res)
                    t = msg.get("type", "")
                    
                    print(f"\n[WS LOG] {msg}")
                    
                    if t == "call_ended":
                        print("\n🔴  Karşı taraf aramayı sonlandırdı.")
                        done.set()
                    else:
                        recv_task = asyncio.create_task(ws.recv())
                except websockets.exceptions.ConnectionClosed:
                    print("\n🔴  Websocket bağlantısı kapandı.")
                    done.set()
                except Exception as e:
                    print(f"\n🔴  WS Hatası: {e}")
                    done.set()
                    
        except asyncio.TimeoutError:
            pass

    print("\n🔴  Bitiriliyor...")
    try:
        api("POST", f"/calls/{call_id}/end", token)
    except Exception as e:
        print(f"   (end: {e})")
    print("✅  Bitti.\n")

# ─── Mod 4: Meşgul Durumu Testi ────────────────────────────────────────────────
async def busy_test_mode(caller_token: str, caller_name: str, callee_token: str, callee_id: int, callee_name: str):
    print(f"\n📞  [Meşgul Testi] @{caller_name} → @{callee_name} aranıyor...")
    
    # 1. Start call
    try:
        d = api("POST", "/calls/start", caller_token, json={"callee_id": callee_id})
    except Exception as e:
        print(f"❌  Arama başlatılamadı: {e}")
        return
        
    call_id = d["call_id"]
    print(f"✅  Arama başlatıldı (call_id={call_id}). Şimdi {callee_name} olarak kabul ediliyor...")
    
    # 2. Accept call
    time.sleep(1)
    try:
        api("POST", f"/calls/{call_id}/accept", callee_token)
    except Exception as e:
        print(f"❌  Arama kabul edilemedi: {e}")
        return
        
    print(f"\n🟢  {caller_name} ve {callee_name} şu an görüşmede!")
    print("    Şimdi telefonunuzdan 'teqlif' kullanıcısı ile bu iki hesaptan birini arayarak 'Meşgul' durumunu test edebilirsiniz.")
    print("    [Enter] tuşuna basarak görüşmeyi sonlandırabilirsiniz...\n")
    
    input()
    
    print("\n🔴  Bitiriliyor...")
    try:
        api("POST", f"/calls/{call_id}/end", caller_token)
    except Exception:
        pass
    print("✅  Bitti.\n")

# ─── Ana menü ─────────────────────────────────────────────────────────────────

def main():
    print("=" * 52)
    print("  Teqlif — Sesli Arama Test")
    print("=" * 52)
    print()
    print("  1  Script telefonu arar   (2gbrain → teqlif)")
    print("  2  Telefon scripti arar   (teqlif → 2gbrain, manuel)")
    print("  3  Telefon arar, oto-kabul")
    print("  4  Meşgul testi           (2gbrain ↔ tucibeyin otomatik görüşür)")
    choice = input("\nSeçim [1/2/3/4]: ").strip()

    print()
    ident = input("2gbrain email/kullanıcı adı [2gbrain]: ").strip() or "2gbrain"
    pwd   = input("Şifre: ").strip()

    print("\nGiriş yapılıyor...")
    try:
        token, uid, uname = login(ident, pwd)
    except Exception as e:
        print(f"❌  {e}")
        sys.exit(1)
    print(f"✅  @{uname} (id={uid})\n")

    if choice == "1":
        phone_u = input("Telefon kullanıcısı [teqlif]: ").strip() or "teqlif"
        print("Kullanıcı aranıyor...")
        cid = lookup_user(phone_u, token)
        if not cid:
            print(f"❌  @{phone_u} bulunamadı")
            sys.exit(1)
        print(f"✅  @{phone_u} id={cid}\n")
        asyncio.run(caller_mode(token, uname, cid, phone_u))

    elif choice in ("2", "3"):
        asyncio.run(callee_mode(token, uname, auto=(choice == "3")))
        
    elif choice == "4":
        ident2 = input("\nİkinci kullanıcı email/kullanıcı adı [tucibeyin]: ").strip() or "tucibeyin"
        pwd2 = input("İkinci kullanıcı şifre: ").strip()
        print("\nİkinci kullanıcıya giriş yapılıyor...")
        try:
            token2, uid2, uname2 = login(ident2, pwd2)
        except Exception as e:
            print(f"❌  {e}")
            sys.exit(1)
        print(f"✅  @{uname2} (id={uid2})\n")
        
        asyncio.run(busy_test_mode(token, uname, token2, uid2, uname2))

    else:
        print("Geçersiz seçim.")
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nİptal.")
