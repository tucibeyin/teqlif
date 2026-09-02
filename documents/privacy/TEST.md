# Privacy & Block — Test Senaryoları

> İmplementasyon referansı: `documents/privacy/PLAN.md` + `documents/privacy/TASK.md`
> Test tarihi: 2026-09-02

---

## Otomatik Test Scripti

Çoğu script testi tek komutla çalıştırılabilir:

```bash
# Gerekli paketler
pip install requests psycopg2-binary redis

# Çalıştır (kullanıcı adı/şifre interaktif sorulur)
cd backend
python3 scripts/test_privacy_block.py

# Ortam değişkenleriyle (interaktif giriş olmadan)
TEST_USER_A=alice TEST_PASS_A=pass1 \
TEST_USER_B=bob   TEST_PASS_B=pass2 \
TEST_USER_C=carol TEST_PASS_C=pass3 \
DB_URL="postgresql://user:pass@localhost/teqlif" \
REDIS_URL="redis://localhost:6379/0" \
python3 scripts/test_privacy_block.py
```

Script dosyası: `backend/scripts/test_privacy_block.py`

---

## Ek Manuel Kontroller İçin Ortam Değişkenleri

Manuel curl komutları çalıştırmak istersen:

```bash
export BASE="https://teqlif.com/api"
export TOKEN_A="eyJ..."   # A kullanıcısının JWT token'ı
export USER_A_ID=101
export TOKEN_B="eyJ..."
export USER_B_ID=102
export TOKEN_C="eyJ..."
export USER_C_ID=103
export PGCONN="postgresql://teqlif_user:PASSWORD@localhost/teqlif"
```

---

## Bölüm 1 — Story Tray (Task 1)

### M1.1 — Pending Follow'da Story Gizleme (Manuel)

**Koşul:** A gizli hesap, B A'yı takip etmek istemiş ama henüz onaylanmamış (pending).

1. B kullanıcısı olarak giriş yap
2. Ana ekrana git → Story tray'i incele
3. A'nın story'si **görünmemeli**
4. A'nın takip isteğini onayla (A kullanıcısıyla gir → Takip İstekleri → Onayla)
5. B olarak ana ekrana geri dön → Story tray'i yenile
6. A'nın story'si **görünmeli**

### M1.2 — Engelleme Sonrası Story Gizleme (Manuel)

**Koşul:** A ve B birbirini takip ediyor.

1. A kullanıcısı olarak B'yi engelle (Profil → ... → Engelle)
2. A olarak ana ekrana git → Story tray'de B'nin story'si **görünmemeli**
3. B olarak giriş yap → Story tray'de A'nın story'si **görünmemeli**

### S1.1 — API ile Story Kontrolü (Script)

```bash
# B'nin görebileceği story'leri listele — A orada olmamalı
curl -s "$BASE/stories/feed" \
  -H "Authorization: Bearer $TOKEN_B" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
users = [s.get('username') for s in data.get('stories', [])]
print('Story tray users:', users)
# A'nın username'ini kontrol et
"
```

---

## Bölüm 2 — Profil Gizliliği (Task 2)

### M2.1 — Gizli Profil — Takipçi Olmayan (Manuel)

**Koşul:** A'nın hesabı gizli (is_private=true). B, A'yı takip etmiyor.

1. B olarak giriş yap
2. A'nın profiline git (arama veya paylaşılan link)
3. Şunlar **görünmemeli:** bio, full_name, sosyal linkler, follower_count, following_count
4. Şunlar **görünmeli:** username, avatar, ilan sayısı, "Takip Et" butonu, live/stream durumu

### M2.2 — Gizli Profil — Onaylı Takipçi (Manuel)

**Koşul:** C, A'nın onaylı takipçisi.

1. C olarak giriş yap
2. A'nın profiline git
3. Tüm profil bilgileri **görünmeli** (bio, follower/following sayıları dahil)

### S2.1 — Profil API Gating (Script)

```bash
# B (takipçi olmayan) A'nın profilini çekiyor
curl -s "$BASE/users/USER_A_USERNAME" \
  -H "Authorization: Bearer $TOKEN_B" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
gated_fields = ['bio', 'full_name', 'follower_count', 'following_count']
for f in gated_fields:
    val = data.get(f)
    status = 'GİZLİ ✓' if val is None else f'AÇIK (!) → {val}'
    print(f'{f}: {status}')
"
```

```bash
# C (onaylı takipçi) A'nın profilini çekiyor — tüm alanlar dolu olmalı
curl -s "$BASE/users/USER_A_USERNAME" \
  -H "Authorization: Bearer $TOKEN_C" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
print('follower_count:', data.get('follower_count'))
print('bio:', data.get('bio'))
"
```

---

## Bölüm 3 — Follower/Following Liste Gizliliği (Task 3)

### M3.1 — Gizli Hesap Takipçi Listesi (Manuel)

**Koşul:** A gizli hesap. B takipçi değil.

1. B olarak A'nın profiline git
2. Follower sayısına tıkla → liste **açılmamalı** / hata mesajı gösterilmeli
3. Following sayısına tıkla → liste **açılmamalı**
4. C (onaylı takipçi) olarak aynı testi yap → liste **açılmalı**

### S3.1 — Follower Liste 403 Kontrolü (Script)

```bash
# B → A'nın follower listesi — 403 bekleniyor
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE/follows/$USER_A_ID/followers" \
  -H "Authorization: Bearer $TOKEN_B")
echo "Status: $STATUS (Beklenen: 403)"

# C → A'nın follower listesi — 200 bekleniyor
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE/follows/$USER_A_ID/followers" \
  -H "Authorization: Bearer $TOKEN_C")
echo "Status: $STATUS (Beklenen: 200)"
```

---

## Bölüm 4 — Block Sistemi (Task 4)

### M4.1 — Teklif Ver Butonu — Engelleme (Manuel)

1. A, B'yi engelle
2. B olarak A'nın bir ilanına git
3. "Teklif Ver" butonu **disabled veya görünmez olmalı**
4. B, C'nin bir ilanına git → "Teklif Ver" normal **aktif olmalı**

### M4.2 — Arama — İlanlar Engelleme Filtresi Yok (Manuel)

> **Beklenen davranış:** Engellediğin kullanıcının ilanları aramada görünür (Karar 6b — tasarım gereği).

1. A, B'yi engelle
2. A olarak arama yap → B'nin ilanları **görünmeli** (bu doğru davranış)
3. Kullanıcı aramasında B **görünmemeli**

### M4.3 — Canlı Yayın — Otomatik Susturma (Manuel)

**Koşul:** A live yayın açıyor. B, A'yı engellemiş.

1. A canlı yayın başlat
2. B yayına katıl → B **otomatik olarak susturulmuş olmalı** (mesaj gönderemez)
3. A viewer listesinde B'yi **görmemeli**

### S4.1 — Teklif Gönderme — Engelleme Kontrolü (Script)

```bash
# A, B'yi engelledikten sonra B A'nın ilanına teklif vermeye çalışıyor
LISTING_ID=999  # A'ya ait bir ilan ID'si
curl -s -X POST "$BASE/listings/$LISTING_ID/offers" \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Type: application/json" \
  -d '{"amount": 100}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
code = data.get('detail', {}).get('code', data.get('detail', ''))
print('Error code:', code, '(Beklenen: OFFER_FORBIDDEN)')
"
```

### S4.2 — DB: Block Kaydı Kontrolü

```bash
psql "$PGCONN" -c "
SELECT blocker_id, blocked_id, created_at
FROM user_blocks
WHERE (blocker_id = $USER_A_ID AND blocked_id = $USER_B_ID)
   OR (blocker_id = $USER_B_ID AND blocked_id = $USER_A_ID);
"
```

---

## Bölüm 5 — Mesaj İstekleri Sistemi (Task 5)

Bu bölüm en kapsamlı test alanıdır. Tüm thread durumları (pending / accepted / declined) test edilir.

### M5.1 — Gizli Hesaba İlk Mesaj → Pending Thread (Manuel)

**Koşul:** A gizli hesap. B, A'yı takip etmiyor.

1. B olarak A'nın profiline git → Mesaj gönder
2. B'nin Mesajlar ekranında → "Mesajlar" sekmesinde A ile konuşma **görünmeli** (bekleyen olarak)
3. A'nın Mesajlar ekranında → "İstekler" sekmesinde B'nin mesajı **görünmeli**
4. A'nın "Mesajlar" dış sekmesinde (alt nav) kırmızı nokta badge **görünmeli**

### M5.2 — Request Banner — Alıcı Görünümü (Manuel)

**Koşul:** M5.1 sonrası. A, B'nin gönderdiği mesaja tıklıyor.

1. A olarak İstekler → B'nin konuşmasına gir
2. Sohbet ekranının **üstünde** bir banner görünmeli:
   - "@B senden mesaj göndermek istiyor" veya benzeri metin
   - **"Kabul Et"** butonu
   - **"Reddet"** butonu

### M5.3 — Request Banner — Gönderen Görünümü (Manuel)

1. B olarak kendi gönderdiği konuşmaya gir
2. Banner **farklı** görünmeli: "İsteğin iletildi, kabul bekleniyor" (bilgilendirici, buton yok)

### M5.4 — Manuel Kabul (Manuel)

**Koşul:** M5.2 sonrası. A, "Kabul Et"e basıyor.

1. Banner **kaybolmalı**
2. A'nın "İstekler" sekmesindeki sayı **azalmalı**
3. Konuşma artık normal Konuşmalar'a taşınmış gibi davranmalı
4. B'ye bildirim gelmeli: "A mesajını kabul etti"

### M5.5 — Soft Decline (Manuel)

**Koşul:** Yeni bir pending thread. A, "Reddet"e basıyor.

1. A'nın "Reddet" tuşuna bastıktan sonra konuşma **A'nın listesinden kaybolmalı**
2. B'nin konuşma listesinde thread **görünmeye devam etmeli** (B habersiz)
3. B'ye **hiçbir bildirim gitmemeli**
4. B tekrar mesaj göndermeye çalışırsa → yeni mesaj gönderilmeli (declined thread yeniden açılır)

### M5.6 — Otomatik Kabul (Auto-Accept) (Manuel)

**Koşul:** B, A'ya mesaj gönderdi → pending. A cevap veriyor (henüz manuel kabul etmeden).

1. A konuşmayı açıp mesaj yazıp gönderiyor
2. Thread durumu otomatik olarak **accepted** olmalı
3. B'ye bildirim gelmeli: "A mesajını kabul etti" + mesaj önizlemesi

### M5.7 — Follow Accept → Thread Promosyonu (Manuel)

**Koşul:** B, A'ya takip isteği gönderdi VE B daha önce A'ya mesaj atmıştı (pending thread var).

1. A, B'nin takip isteğini kabul ediyor
2. DB'de o thread'in durumu **pending → accepted** olmuş olmalı (script ile doğrula)
3. B'nin konuşması artık normal konuşma gibi davranmalı

### M5.8 — Gizlilik Kapatılınca Toplu Promosyon (Manuel)

**Koşul:** A gizli hesap. Birden fazla pending thread var.

1. A, Ayarlar → Hesap Gizliliği → Kapalı olarak ayarla
2. DB'de A'ya ait tüm pending thread'ler **accepted** olmuş olmalı (script ile doğrula)
3. Redis'te `msg:unread:request:{A_ID}` key'i **silinmiş olmalı**

### S5.1 — Thread Durumu API Kontrolü (Script)

```bash
# B → A'ya thread durumu
curl -s "$BASE/messages/thread/$USER_A_ID/status" \
  -H "Authorization: Bearer $TOKEN_B" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('status:', data.get('status'))        # pending / accepted / declined / null
print('is_initiator:', data.get('is_initiator'))  # True = B gönderici
"

# A → B'ye bakış
curl -s "$BASE/messages/thread/$USER_B_ID/status" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('status:', data.get('status'))        # pending bekleniyor
print('is_initiator:', data.get('is_initiator'))  # False = A alıcı
"
```

### S5.2 — İstekler Listesi API (Script)

```bash
# A'nın gelen isteklerini listele
curl -s "$BASE/messages/requests" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'İstek sayısı: {len(data)}')
for req in data:
    print(f'  - user_id={req.get(\"user_id\")} username={req.get(\"username\")}')
"
```

### S5.3 — Manuel Kabul API (Script)

```bash
# A, B'nin isteğini kabul ediyor
curl -s -X POST "$BASE/messages/requests/$USER_B_ID/accept" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
print(json.load(sys.stdin))
"

# Doğrulama: thread durumu accepted olmuş mu?
curl -s "$BASE/messages/thread/$USER_B_ID/status" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
data = json.load(sys.stdin)
status = data.get('status')
print(f'Thread status: {status} (Beklenen: accepted)')
"
```

### S5.4 — Decline API (Script)

```bash
# A, B'nin isteğini reddediyor
curl -s -X POST "$BASE/messages/requests/$USER_B_ID/decline" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
print(json.load(sys.stdin))
"

# Doğrulama: thread artık yok olmalı
curl -s "$BASE/messages/thread/$USER_B_ID/status" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
data = json.load(sys.stdin)
status = data.get('status')
print(f'Thread status: {status} (Beklenen: declined)')
"
```

### S5.5 — DB: message_threads Tablosu Kontrolü

```bash
# Tüm thread'leri listele
psql "$PGCONN" -c "
SELECT
  user_a_id,
  user_b_id,
  initiator_id,
  status,
  created_at
FROM message_threads
ORDER BY created_at DESC
LIMIT 20;
"

# A ve B arasındaki spesifik thread
psql "$PGCONN" -c "
SELECT status, initiator_id, created_at
FROM message_threads
WHERE (user_a_id = LEAST($USER_A_ID, $USER_B_ID)
  AND user_b_id = GREATEST($USER_A_ID, $USER_B_ID));
"

# Gizlilik kapatılınca toplu promosyon doğrulaması:
# A'ya ait tüm pending thread yok olmalı
psql "$PGCONN" -c "
SELECT COUNT(*) as pending_count
FROM message_threads
WHERE (user_a_id = $USER_A_ID OR user_b_id = $USER_A_ID)
  AND status = 'pending';
-- Gizlilik açıkken: 0 bekleniyor
"
```

### S5.6 — Redis: Request Count Kontrolü

```bash
# VPS'te çalıştır
redis-cli GET "msg:unread:request:$USER_A_ID"
# Beklenen: pending thread sayısı (int string) veya null

# Kabul/reddet sonrası azalmış mı?
# accept veya decline sonrasında tekrar kontrol et
redis-cli GET "msg:unread:request:$USER_A_ID"
```

### S5.7 — Konuşma Listesi — Initiator Görünürlüğü (Script)

```bash
# B (initiator) kendi konuşmalar listesinde A görünmeli
curl -s "$BASE/messages/conversations" \
  -H "Authorization: Bearer $TOKEN_B" | python3 -c "
import sys, json
data = json.load(sys.stdin)
user_ids = [c.get('user_id') for c in data]
found = $USER_A_ID in user_ids
print(f'A konuşmalar listesinde: {\"VAR ✓\" if found else \"YOK (!) — hata\"}')
"

# A (alıcı) kendi konuşmalar listesinde B görünmemeli (İstekler'de görünmeli)
curl -s "$BASE/messages/conversations" \
  -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
data = json.load(sys.stdin)
user_ids = [c.get('user_id') for c in data]
found = $USER_B_ID in user_ids
print(f'B, A konuşmalar listesinde: {\"VAR (!) — Konuşmalar\\'a sızmamalı\" if found else \"YOK ✓\"}')
"
```

---

## Bölüm 6 — Gizlilik Bildirim Pankartı (Task 6)

### M6.1 — Pankart Gösterimi — Açık Hesap (Manuel)

**Koşul:** Açık hesap (is_private=false). Pankart daha önce kapatılmamış.

1. Uygulamayı ilk kez yükle (veya uygulama verisini temizle)
2. Kendi profilini aç
3. Profil yüklendikten sonra **pankart görünmeli**: "Profilin herkese açık" + "Ayarlara git" linki + X butonu

### M6.2 — Pankart Kapatma ve Kalıcı Gizleme (Manuel)

1. M6.1 sonrası X butonuna bas
2. Pankart **kaybolmalı**
3. Profil ekranından çık ve tekrar gir → pankart **görünmemeli**
4. Uygulamayı kapat ve tekrar aç → pankart **hâlâ görünmemeli**

### M6.3 — Pankart — Gizli Hesapta Görünmemeli (Manuel)

1. Ayarlar → Hesap Gizliliği → Açık
2. Kendi profilini aç
3. Pankart **görünmemeli**

### M6.4 — "Ayarlara Git" Linki (Manuel)

1. Pankart görünürken "Ayarlara git" linkine tıkla
2. **Ayarlar ekranı açılmalı**
3. Pankart hâlâ açık olmalı (sadece X ile kapanır)

---

## Bölüm 7 — Uçtan Uca Akış Testi

### M7.1 — Tam Mesaj İsteği Akışı (Manuel)

Bu test tüm sistemi uçtan uca doğrular. İki cihaz gerekir.

**Cihaz A:** A kullanıcısı (gizli hesap)
**Cihaz B:** B kullanıcısı (takipçi değil)

| Adım | Aksiyon | Beklenen Sonuç |
|------|---------|----------------|
| 1 | A hesabını gizli yap (Ayarlar) | — |
| 2 | B, A profiline git → Mesaj gönder: "Merhaba" | Gönderildi animasyonu |
| 3 | B, Mesajlar → Konuşmalar sekmesi | A konuşması görünüyor, banner: "İstek bekleniyor" |
| 4 | A, Mesajlar → alt nav badge kırmızı nokta | Görünüyor |
| 5 | A, Mesajlar → İstekler sekmesi | B'nin isteği görünüyor |
| 6 | A, B'nin konuşmasına gir | Banner: "B mesaj göndermek istiyor" + Kabul Et / Reddet |
| 7 | A, "Kabul Et"e bas | Banner kaybolur |
| 8 | B'ye bildirim gelir | "A mesajını kabul etti" |
| 9 | A ve B artık normal konuşma yapabilir | — |

### M7.2 — Otomatik Kabul Akışı (Manuel)

| Adım | Aksiyon | Beklenen Sonuç |
|------|---------|----------------|
| 1 | B, A'ya mesaj gönderir (pending thread) | — |
| 2 | A, İstekler'e girmeden direk konuşmaya girer ve yanıt yazar | — |
| 3 | Thread durumu auto-accepted olur | Banner kaybolur |
| 4 | B'ye bildirim gelir | "A mesajını kabul etti" + mesaj metni önizlemesi |

---

## Bölüm 8 — Regresyon Kontrolleri

Bu testler mevcut özelliklerin bozulmadığını doğrular.

### M8.1 — Normal Konuşma Akışı Bozulmamış (Manuel)

**Koşul:** A ve B zaten takipçi.

1. B → A'ya mesaj gönder
2. İstekler sekmesine **düşmemeli** → normal Konuşmalar'da görünmeli
3. A bildirimi almalı (eğer bildirim açıksa)

### M8.2 — Açık Hesaba Mesaj — Pending Yok (Manuel)

**Koşul:** A'nın hesabı açık (is_private=false). B ve A birbirini takip etmiyor.

1. B → A'ya mesaj gönder
2. Thread **doğrudan accepted** olmalı (pending değil)
3. A'nın İstekler sekmesinde **görünmemeli**

### S8.1 — Açık Hesap Thread Durumu (Script)

```bash
# A hesabı açıkken B mesaj gönderdikten sonra thread durumu
curl -s "$BASE/messages/thread/$USER_A_ID/status" \
  -H "Authorization: Bearer $TOKEN_B" | python3 -c "
import sys, json
data = json.load(sys.stdin)
status = data.get('status')
print(f'Thread status: {status} (Beklenen: accepted — açık hesapta pending olmamalı)')
"
```

---

## Hızlı Referans: Test Kontrol Listesi

```
[ ] M1.1 — Pending follow story'si gizli
[ ] M1.2 — Block sonrası story gizli (iki yön)
[ ] M2.1 — Gizli profil sınırlı bilgi (takipçi değil)
[ ] M2.2 — Gizli profil tam bilgi (onaylı takipçi)
[ ] M3.1 — Follower listesi gizli (takipçi değil)
[ ] M4.1 — Block'lu kullanıcıya teklif verilemiyor
[ ] M4.2 — Arama'da ilanlar engelsiz görünüyor (tasarım gereği)
[ ] M4.3 — Live'da block → otomatik mute
[ ] M5.1 — Gizli hesaba mesaj → pending thread, İstekler'de görünür
[ ] M5.2 — Request banner alıcı: Kabul Et / Reddet butonları
[ ] M5.3 — Request banner gönderen: bilgilendirici mesaj
[ ] M5.4 — Manuel kabul → thread accepted, B'ye bildirim
[ ] M5.5 — Soft decline → B habersiz, thread declined
[ ] M5.6 — Auto-accept → A cevap yazınca accepted, B'ye bildirim
[ ] M5.7 — Follow accept → pending thread promoted
[ ] M5.8 — Gizlilik kapat → tüm pending thread'ler accepted
[ ] M6.1 — Privacy banner açık hesapta görünür
[ ] M6.2 — Banner kapatılınca kalıcı gizlenir
[ ] M6.3 — Privacy banner gizli hesapta görünmez
[ ] M6.4 — "Ayarlara git" linki çalışıyor
[ ] M7.1 — Uçtan uca tam akış
[ ] M7.2 — Auto-accept akışı
[ ] M8.1 — Mevcut takipçi konuşmaları bozulmamış
[ ] M8.2 — Açık hesaba mesaj pending değil
```
