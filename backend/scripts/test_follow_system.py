import requests
import getpass
import time

BASE_URL = "https://www.teqlif.com/api"

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
    return {"Authorization": f"Bearer {token}", "Accept-Language": "tr"}

def set_private(username, token, is_private):
    print(f"[{username}] Hesap gizliliği ayarlanıyor: {'Gizli' if is_private else 'Açık'}")
    resp = requests.patch(f"{BASE_URL}/auth/me", headers=get_headers(token), json={
        "is_private": is_private
    })
    assert resp.status_code == 200, f"Hesap gizliliği değiştirilemedi: {resp.text}"

def unfollow(username, token, target_username, target_id, expect_error=False):
    print(f"[{username}] -> [{target_username}] Takipten çıkılıyor...")
    resp = requests.delete(f"{BASE_URL}/follows/{target_id}", headers=get_headers(token))
    if expect_error:
        assert resp.status_code != 200, "Hata bekleniyordu ama 200 döndü!"
        print(f"[{username}] Beklenen hata alındı: {resp.json().get('detail')}")
    else:
        if resp.status_code in [200, 404]:
            print(f"[{username}] -> [{target_username}] Takipten çıkıldı veya zaten takip edilmiyor.")
        else:
            print(f"Takipten çıkılamadı: {resp.text}")

def follow(username, token, target_username, target_id, expect_error=False):
    print(f"[{username}] -> [{target_username}] Takip et butonuna basılıyor...")
    resp = requests.post(f"{BASE_URL}/follows/{target_id}", headers=get_headers(token))
    if expect_error:
        assert resp.status_code != 200, "Hata bekleniyordu ama 200 döndü!"
        print(f"[{username}] Beklenen hata alındı: {resp.json().get('detail')}")
    else:
        assert resp.status_code == 200, f"Takip hatası: {resp.text}"
        print(f"[{username}] İstek başarıyla gönderildi/onaylandı.")

def check_follow_requests(username, token):
    print(f"[{username}] Takip istekleri kontrol ediliyor...")
    resp = requests.get(f"{BASE_URL}/follows/requests", headers=get_headers(token))
    assert resp.status_code == 200, f"Takip istekleri çekilemedi: {resp.text}"
    reqs = resp.json()
    print(f"[{username}] Toplam {len(reqs)} bekleyen takip isteği var.")
    return reqs

def accept_request(username, token, follower_id, expect_error=False):
    print(f"[{username}] İstek kabul ediliyor (Kullanıcı ID: {follower_id})...")
    resp = requests.post(f"{BASE_URL}/follows/{follower_id}/accept", headers=get_headers(token))
    if expect_error:
        assert resp.status_code != 200, "Hata bekleniyordu ama 200 döndü!"
        print(f"[{username}] Beklenen hata alındı: {resp.json().get('detail')}")
    else:
        assert resp.status_code == 200, f"İstek kabul edilemedi: {resp.text}"
        print(f"[{username}] İstek başarıyla kabul edildi!")

def reject_request(username, token, follower_id, expect_error=False):
    print(f"[{username}] İstek reddediliyor (Kullanıcı ID: {follower_id})...")
    resp = requests.post(f"{BASE_URL}/follows/{follower_id}/reject", headers=get_headers(token))
    if expect_error:
        assert resp.status_code != 200, "Hata bekleniyordu ama 200 döndü!"
        print(f"[{username}] Beklenen hata alındı: {resp.json().get('detail')}")
    else:
        assert resp.status_code == 200, f"İstek reddedilemedi: {resp.text}"
        print(f"[{username}] İstek başarıyla reddedildi!")

def get_followers(username, token, user_id):
    resp = requests.get(f"{BASE_URL}/follows/{user_id}/followers", headers=get_headers(token))
    assert resp.status_code == 200, f"Takipçiler çekilemedi: {resp.text}"
    return resp.json()

def get_following(username, token, user_id):
    resp = requests.get(f"{BASE_URL}/follows/{user_id}/following", headers=get_headers(token))
    assert resp.status_code == 200, f"Takip edilenler çekilemedi: {resp.text}"
    return resp.json()

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
    print("=== Teqlif Follow System Test Script (Full Coverage) ===")
    
    teqlif_pass = getpass.getpass("Lütfen 'teqlif' kullanıcısının şifresini girin: ")
    tesbih_pass = getpass.getpass("Lütfen 'tesbih' kullanıcısının şifresini girin: ")

    teqlif_token = login("teqlif", teqlif_pass)
    tesbih_token = login("tesbih", tesbih_pass)
    
    print("\n--- Hazırlık ---")
    teqlif_profile = check_profile("tesbih", tesbih_token, "teqlif")
    teqlif_id = teqlif_profile["id"]
    tesbih_profile = check_profile("teqlif", teqlif_token, "tesbih")
    tesbih_id = tesbih_profile["id"]
    
    try:
        requests.delete(f"{BASE_URL}/follows/{tesbih_id}", headers=get_headers(teqlif_token))
        requests.delete(f"{BASE_URL}/follows/{teqlif_id}", headers=get_headers(tesbih_token))
        requests.post(f"{BASE_URL}/follows/{teqlif_id}/reject", headers=get_headers(tesbih_token))
        requests.post(f"{BASE_URL}/follows/{tesbih_id}/reject", headers=get_headers(teqlif_token))
    except:
        pass


    print("\n=======================================================")
    print(" SENARYO 1: KENDİNİ TAKİP ETMEYE ÇALIŞMA (Hata)")
    print("=======================================================")
    follow("teqlif", teqlif_token, "teqlif", teqlif_id, expect_error=True)


    print("\n=======================================================")
    print(" SENARYO 2: OLMAYAN KULLANICIYI TAKİP ETMEYE ÇALIŞMA (Hata)")
    print("=======================================================")
    follow("teqlif", teqlif_token, "olmayan_biri", 999999, expect_error=True)


    print("\n=======================================================")
    print(" SENARYO 3: TAKİP EDİLMEYEN KİŞİYİ TAKİPTEN ÇIKMA (Hata)")
    print("=======================================================")
    unfollow("teqlif", teqlif_token, "tesbih", tesbih_id, expect_error=True)


    print("\n=======================================================")
    print(" SENARYO 4: OLMAYAN BİR İSTEĞİ KABUL/RED ETMEYE ÇALIŞMA (Hata)")
    print("=======================================================")
    accept_request("tesbih", tesbih_token, teqlif_id, expect_error=True)
    reject_request("tesbih", tesbih_token, teqlif_id, expect_error=True)


    print("\n=======================================================")
    print(" SENARYO 5: GİZLİ HESABA TAKİP İSTEĞİ GÖNDERME VE KABUL")
    print("=======================================================")
    set_private("tesbih", tesbih_token, True)
    time.sleep(1)

    follow("teqlif", teqlif_token, "tesbih", tesbih_id)
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("follow_status") == "pending", "Status 'pending' olmalıydı!"
    
    print("\n--- HATA TESTİ: ZATEN İSTEK ATILMIŞKEN TEKRAR ATMA ---")
    follow("teqlif", teqlif_token, "tesbih", tesbih_id, expect_error=True)

    reqs = check_follow_requests("tesbih", tesbih_token)
    teqlif_req = next((r for r in reqs if r["username"] == "teqlif"), None)
    assert teqlif_req is not None, "Teqlif isteklerde bulunamadı!"
    
    accept_request("tesbih", tesbih_token, teqlif_id)
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("is_following") == True, "Takip durumu True olmalıydı!"

    print("\n--- HATA TESTİ: ZATEN TAKİP EDERKEN TEKRAR TAKİP ETME ---")
    follow("teqlif", teqlif_token, "tesbih", tesbih_id, expect_error=True)

    print("\n=======================================================")
    print(" SENARYO 6: LİSTELERİN KONTROLÜ (Followers & Following)")
    print("=======================================================")
    followers = get_followers("tesbih", tesbih_token, tesbih_id)
    assert any(u["id"] == teqlif_id for u in followers), "Teqlif, Tesbih'in takipçileri arasında olmalı!"
    
    following = get_following("teqlif", teqlif_token, teqlif_id)
    assert any(u["id"] == tesbih_id for u in following), "Tesbih, Teqlif'in takip ettikleri arasında olmalı!"

    
    print("\n=======================================================")
    print(" SENARYO 7: GİZLİ HESABA TAKİP İSTEĞİ GÖNDERME VE REDDETME")
    print("=======================================================")
    unfollow("teqlif", teqlif_token, "tesbih", tesbih_id)
    time.sleep(1)

    follow("teqlif", teqlif_token, "tesbih", tesbih_id)
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("follow_status") == "pending", "Status 'pending' olmalıydı!"

    reject_request("tesbih", tesbih_token, teqlif_id)
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("is_following") == False, "İstek reddedildiği için False olmalı!"
    assert profile.get("follow_status") == "none", "İstek silindiği için 'none' olmalı!"


    print("\n=======================================================")
    print(" SENARYO 8: AÇIK HESABA DİREKT TAKİP (ANINDA ONAY)")
    print("=======================================================")
    set_private("tesbih", tesbih_token, False)
    time.sleep(1)

    follow("teqlif", teqlif_token, "tesbih", tesbih_id)
    profile = check_profile("teqlif", teqlif_token, "tesbih")
    assert profile.get("is_following") == True, "Hesap açık olduğu için direkt takip etmeliydi!"
    
    # Final cleanup
    unfollow("teqlif", teqlif_token, "tesbih", tesbih_id)

    print("\n✅ TÜM TESTLER BAŞARIYLA GEÇTİ!")

if __name__ == "__main__":
    main()
