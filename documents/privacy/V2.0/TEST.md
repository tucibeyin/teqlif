# Privacy V2.0 — Son Kullanıcı Test Senaryoları

> **Kapsam:** Follow-based mesajlaşma ve arama izni modeli (Karar 3 + Karar 9)
> **Referans:** `documents/privacy/V2.0/privacy.md`

---

## Test Kullanıcıları

| Kullanıcı | Rol |
|-----------|-----|
| **Ali** | Mesaj/arama başlatan (initiator) |
| **Buse** | Karşı taraf (receiver / acceptor) |

---

## 1. Mesajlaşma — Thread Tipi

### 1.1 Buse Ali'yi takip etmiyor → Mesaj isteği

**Senaryo:** Ali, Buse'ye ilk mesajı gönderir. Buse Ali'yi takip etmiyor.

**Adımlar:**
1. Ali → Buse profil ekranı → Mesaj ikonuna dokun
2. Ali bir mesaj yaz ve gönder

**Beklenen:**
- Buse'nin "Mesaj İstekleri" sekmesinde Ali'nin konuşması görünür
- Buse'nin gelen kutusunda (normal konuşmalar) **görünmez**
- Ali'nin kendi ekranında konuşma normal açılır (gönderebildi)

---

### 1.2 Buse Ali'yi takip ediyor → Direkt mesaj (istek yok)

**Senaryo:** Buse, Ali'yi önceden takip ediyor. Ali Buse'ye ilk mesajı gönderir.

**Adımlar:**
1. Ali → Buse profil ekranı → Mesaj ikonuna dokun
2. Ali bir mesaj yaz ve gönder

**Beklenen:**
- Konuşma Buse'nin **gelen kutusunda** (normal) görünür
- "Mesaj İstekleri" sekmesine **düşmez**

---

### 1.3 Buse takip isteğini kabul eder → Pending thread kabul edilir

**Senaryo:** TC 1.1 sonrası — Ali'nin mesajı Buse'nin isteğinde bekliyor.

**Adımlar:**
1. Buse → Takip İstekleri → Ali'yi kabul et

**Beklenen:**
- Buse'nin "Mesaj İstekleri" sekmesindeki Ali konuşması gelen kutusuna taşınır
- Konuşma artık `accepted` status'ta

---

### 1.4 Buse Ali'yi takip isteğini reddeder → Thread etkilenmez

**Senaryo:** TC 1.1 sonrası — Ali'nin mesajı Buse'nin isteğinde bekliyor.

**Adımlar:**
1. Buse → Takip İstekleri → Ali'yi reddet

**Beklenen:**
- Thread durumu değişmez (hâlâ `pending`)
- Ali mesaj göndermeye devam edebilir (thread var)
- Buse'de İstekler sekmesinde kalmaya devam eder

---

### 1.5 "Mesaj İstekleri" sekmesi boş durum metni

**Senaryo:** Kullanıcının hiç mesaj isteği yokken sekmeyi açar.

**Beklenen:**
- "Seni takip etmeyen kişilerden gelen mesajlar burada görünecek" metni görünür

---

## 2. Arama — Profil Ekranı Ara Butonu

### 2.1 Karşılıklı takip → Ara butonu aktif

**Senaryo:** Ali ve Buse birbirini takip ediyor.

**Adımlar:**
1. Ali → Buse'nin profil ekranını aç

**Beklenen:**
- AppBar'da `call` (dolu) ikonu görünür, **aktif**
- Dokunulduğunda arama başlar

---

### 2.2 Karşılıklı takip yok, thread yok → Ara butonu disabled + ⓘ

**Senaryo:** Ali ve Buse arasında hiç takip veya konuşma yok.

**Adımlar:**
1. Ali → Buse'nin profil ekranını aç

**Beklenen:**
- AppBar'da `call_outlined` (çerçeveli) ikon görünür, **gri/disabled**
- Yanında ⓘ ikonu var
- ⓘ'ya dokunulduğunda: "Arama izni yok — karşılıklı takip veya arama izni gerekiyor" toastı çıkar
- Disabled butona dokunulduğunda hiçbir şey olmaz

---

### 2.3 Buse → Ali takip ediyor (tek yön) — Buse'nin perspektifi

**Senaryo:** Buse Ali'yi takip ediyor, Ali Buse'yi takip etmiyor.

**Adımlar:**
1. Buse → Ali'nin profil ekranını aç

**Beklenen:**
- Buse'nin ekranında ara butonu **aktif** (follower → followed araya bilir)

---

### 2.4 Ali → Buse takip ediyor (tek yön) + accepted thread + call_allowed=false → Ara butonu disabled

**Senaryo:** Ali Buse'yi takip ediyor, aralarında accepted thread var, Buse arama izni vermemiş.

**Adımlar:**
1. Ali → Buse'nin profil ekranını aç

**Beklenen:**
- Ara butonu **disabled** + ⓘ görünür

---

### 2.5 Ali → Buse takip ediyor (tek yön) + accepted thread + call_allowed=true → Ara butonu aktif

**Senaryo:** TC 2.4 ile aynı ama Buse arama iznini açmış.

**Adımlar:**
1. Ali → Buse'nin profil ekranını aç

**Beklenen:**
- Ara butonu **aktif**

---

## 3. Arama — Mesaj Thread Ekranı

### 3.1 Accepted thread — Acceptor (Buse) toggle'ı görür

**Senaryo:** Ali ve Buse arasında accepted thread var. Karşılıklı takip yok.

**Adımlar:**
1. Buse → Ali ile konuşmayı aç

**Beklenen:**
- Konuşma ekranında ince bir satır görünür: "Arama izni" + Switch + ⓘ
- ⓘ'ya dokunulduğunda: "Arama iznini sen kontrol ediyorsun" toastı çıkar
- Switch başlangıçta **kapalı** (call_allowed=false)

---

### 3.2 Accepted thread — Initiator (Ali) toggle görmez, sadece ⓘ görür

**Senaryo:** TC 3.1 ile aynı thread. Ali'nin perspektifi.

**Adımlar:**
1. Ali → Buse ile konuşmayı aç

**Beklenen:**
- Konuşma ekranında ince bir satır görünür: "Arama izni" + ⓘ (switch yok)
- ⓘ'ya dokunulduğunda: "Arama izni karşı taraf tarafından ayarlanır" toastı çıkar

---

### 3.3 Acceptor toggle'ı açar → Initiator'ın ara butonu aktif olur

**Senaryo:** TC 3.1 devamı. Buse switch'i açıyor.

**Adımlar:**
1. Buse → Switch'i aç (call_allowed=true)
2. Ali'nin ekranına geç (veya WS eventi bekle)

**Beklenen:**
- Buse'nin switch'i açık konumda kalır
- Ali'nin mesaj thread ekranındaki ara butonu **aktif** olur (WS can_call_changed eventi)
- Ali'nin profil ekranında da (yeniden açıldığında) ara butonu aktif görünür

---

### 3.4 Acceptor toggle'ı kapatır → Initiator'ın ara butonu disabled olur

**Senaryo:** TC 3.3 devamı. Buse switch'i kapatıyor.

**Adımlar:**
1. Buse → Switch'i kapat (call_allowed=false)

**Beklenen:**
- Ali'nin mesaj thread ekranındaki ara butonu **disabled** + ⓘ olur

---

### 3.5 Pending thread'de call permission satırı görünmez

**Senaryo:** Ali mesaj istedi, Buse henüz kabul etmedi.

**Adımlar:**
1. Buse → Mesaj İstekleri → Ali'nin konuşmasını aç

**Beklenen:**
- "Arama izni" satırı **görünmez** (sadece accepted thread'de çıkar)

---

## 4. Arama — CALL_FORBIDDEN Toast

### 4.1 İzin olmadan arama girişimi → Toast

**Senaryo:** Ali'nin `can_call=false` olduğu bir kullanıcıyı aramaya çalışır (eski bir bildirim linki veya beklenmedik durum).

**Beklenen:**
- "Bu kullanıcıyı şu an arayamazsın" error toastı çıkar
- Arama başlamaz

---

## 5. WS Gerçek Zamanlı Güncellemeler

### 5.1 Follow kabul → can_call anında güncellenir

**Senaryo:** Ali Buse'yi takibi bekliyor. Buse isteği kabul eder.

**Adımlar:**
1. Ali ve Buse mesaj thread ekranını aynı anda açık tutsun
2. Buse → Takip İsteklerinden Ali'yi kabul et

**Beklenen:**
- Ali'nin ekranında ara butonu beklemeden **aktif** olur (WS can_call_changed)

---

### 5.2 Unfollow → can_call anında güncellenir

**Senaryo:** Ali ve Buse karşılıklı takipte. Buse Ali'yi takipten çıkarır.

**Adımlar:**
1. Ali mesaj thread ekranını açık tutsun
2. Buse → Ali'nin profilinden takipten çık

**Beklenen:**
- Ali'nin ekranında ara butonu **disabled** olur

---

## 6. Kenarlık Durumları

### 6.1 Kendi profilinde ara butonu yok

**Beklenen:** Kendi profilini açtığında AppBar'da ara ikonu görünmez.

---

### 6.2 Engellenen kullanıcıda ara butonu yok

**Beklenen:** Engellediğin kullanıcının profilini açtığında ara ikonu görünmez (profil zaten kısıtlı).

---

### 6.3 Karşılıklı takip — call_allowed toggle'ının etkisi yok

**Senaryo:** Ali ve Buse karşılıklı takipte. Buse toggle'ı kapatır.

**Beklenen:**
- Karşılıklı takipte `can_call` her zaman true → Ali yine araya bilir
- Toggle'ın durumu UI'da değişir ama etki etmez (backend `_compute_can_call` mutual follow → True döner)
