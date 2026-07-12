import requests
import getpass
import time

BASE_URL = "https://www.teqlif.com/api"
# Veya local'de test etmek istersen:
# BASE_URL = "http://localhost:8000/api"

def login(username, password):
    print(f"[{username}] Giriş yapılıyor...")
    resp = requests.post(f"{BASE_URL}/auth/login", json={
        "login_identifier": username,
        "password": password
    })
    if resp.status_code == 200:
        print(f"[{username}] Başarıyla giriş yapıldı. Token alındı.")
        return resp.json()["access_token"]
    else:
        print(f"[{username}] Giriş başarısız: {resp.text}")
        exit(1)

def get_headers(token):
    return {"Authorization": f"Bearer {token}"}

def set_private(username, token, is_private):
    print(f"[{username}] Hesap gizliliği ayarlanıyor: {'Gizli' if is_private else 'Açık'}")
    resp = requests.patch(f"{BASE_URL}/auth/me", headers=get_headers(token), json={
        "is_private": is_private
    })
    assert resp.status_code == 200, f"Hesap gizliliği değiştirilemedi: {resp.text}"

def unfollow(username, token, target_username, target_id):
    print(f"[{username}] -> [{target_username}] Takipten çıkılıyor...")
    resp = requests.delete(f"{BASE_URL}/follows/{target_id}", headers=get_headers(token))
    if resp.status_code in [200, 404]:
        print(f"[{username}] -> [{target_username}] Takipten çıkıldı veya zaten takip edilmiyor.")
    else:
        print(f"Takipten çıkılamadı: {resp.text}")

def follow(username, token, target_username, target_id):
    print(f"[{username}] -> [{target_username}] Takip et butonuna basılıyor...")
    resp = requests.post(f"{BASE_URL}/follows/{target_id}", headers=get_headers(token))
    if resp.status_code == 200:
        print(f"[{username}] İstek başarıyla gönderildi.")
    elif resp.status_code == 400:
        print(f"[{username}] Uyarı: {resp.json().get('detail')}")
    else:
        print(f"Takip hatası: {resp.text}")

def check_follow_requests(username, token):
    print(f"[{username}] Takip istekleri kontrol ediliyor...")
    resp = requests.get(f"{BASE_URL}/follows/requests", headers=get_headers(token))
    assert resp.status_code == 200, f"Takip istekleri çekilemedi: {resp.text}"
    reqs = resp.json()
    print(f"[{username}] Toplam {len(reqs)} bekleyen takip isteği var.")
    return reqs

def accept_request(username, token, follower_id):
    print(f"[{username}] İstek kabul ediliyor (Kullanıcı ID: {follower_id})...")
    resp = requests.post(f"{BASE_URL}/follows/{follower_id}/accept", headers=get_headers(token))
    assert resp.status_code == 200, f"İstek kabul edilemedi: {resp.text}"
    print(f"[{username}] İstek başarıyla kabul edildi!")

def check_profile(username, token, target_username):
    print(f"[{username}] -> [{target_username}] Profil bilgileri çekiliyor...")
    resp = requests.get(f"{BASE_URL}/users/{target_username}", headers=get_headers(token))
    assert resp.status_code == 200, f"Profil çekilemedi: {resp.text}"
    data = resp.json()
    print(f"[{username}] Gözünden [{target_username}] profili:")
    print(f"   - is_following: {data.get('is_following')}")
    print(f"   - is_private: {data.get('is_private')}")
    print(f"   - follow_status: {data.get('follow_status')}")
    return data

def main():
    print("=== Teqlif Follow System Test Script ===")
    
    # Şifreleri al
    teqlif_pass = getpass.getpass("Lütfen 'teqlif' kullanıcısının şifresini girin: ")
    tesbih_pass = getpass.getpass("Lütfen 'tesbih' kullanıcısının şifresini girin: ")

    # Giriş yap
    teqlif_token = login("teqlif", teqlif_pass)
    tesbih_token = login("tesbih", tesbih_pass)
    
    # ID'leri bul
    print("\n--- Hazırlık ---")
    teqlif_profile = check_profile("tesbih", tesbih_token, "teqlif")
    teqlif_id = teqlif_profile["id"]
    tesbih_profile = check_profile("teqlif", teqlif_token, "tesbih")
    tesbih_id = tesbih_profile["id"]
    
    # Ortamı Temizle
    unfollow("teqlif", teqlif_token, "tesbih", tesbih_id)
    unfollow("tesbih", tesbih_token, "teqlif", teqlif_id)

    print("\n=======================================================")
    print(" SENARYO 1: GİZLİ HESABA TAKİP İSTEĞİ GÖNDERME VE KABUL")
    print("=======================================================")
    
    set_private("tesbih", tesbih_token, True)
    time.sleep(1)

    # Teqlif, Tesbih'i takip etmeye çalışır
    follow("teqlif", teqlif_token, "tesbih", tesbih_id)
    
    # Teqlif profili kontrol eder
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("follow_status") == "pending", "Status 'pending' olmalıydı!"
    
    # Tesbih kendi isteklerini kontrol eder
    reqs = check_follow_requests("tesbih", tesbih_token)
    teqlif_req = next((r for r in reqs if r["username"] == "teqlif"), None)
    assert teqlif_req is not None, "Teqlif isteklerde bulunamadı!"
    
    # Tesbih isteği onaylar
    accept_request("tesbih", tesbih_token, teqlif_id)
    
    # Teqlif tekrar profilini kontrol eder
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("is_following") == True, "Takip durumu True olmalıydı!"


    print("\n=======================================================")
    print(" SENARYO 2: AÇIK HESABA DİREKT TAKİP (ANINDA ONAY)")
    print("=======================================================")
    
    unfollow("teqlif", teqlif_token, "tesbih", tesbih_id)
    time.sleep(1)
    
    set_private("tesbih", tesbih_token, False)
    time.sleep(1)

    # Teqlif, Tesbih'i takip etmeye çalışır
    follow("teqlif", teqlif_token, "tesbih", tesbih_id)
    
    # Teqlif profili kontrol eder
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("is_following") == True, "Hesap açık olduğu için direkt takip etmeliydi!"
    
    print("\n✅ TÜM TESTLER BAŞARIYLA GEÇTİ!")

if __name__ == "__main__":
    main()
