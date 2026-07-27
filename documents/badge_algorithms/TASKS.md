# 📋 Teqlif Rozet Algoritmaları - Uygulama ve İş Takip Listesi (TASKS)

Bu döküman, `PLAN.md` içerisinde tanımlanan mimari modernizasyon adımlarının hayata geçirilmesi için hazırlanmış adım adım iş takip listesidir.

---

## 🏗️ Faz 1: Satıcı Rozet Kapsamının Genişletilmesi (`worker.py`)
- [x] **1.1. ClickHouse Etkinlik Analizi ve Şema Kontrolü**
  - [x] `user_events` ve `analytics_events` tablolarında normal satış etkinliklerinin (`offer_accepted`, `listing_sold`, `order_completed`) loglanma biçimlerinin kontrol edilmesi.
  - [x] Eksik etkinlik türleri varsa event logging pipeline'ına eklenmesi.
- [x] **1.2. `compute_seller_badges_task` Sorgu Revizyonu**
  - [x] `backend/app/worker.py` içindeki hem eşik (p75/p50) hesaplama sorgusuna hem de satıcı skor sorgusuna normal satış etkinliklerinin (`offer_accepted`, `listing_sold`, `order_completed`) dahil edilmesi.
  - [x] `won / total` dönüşüm oranı formülünün tüm ticaret biçimlerini (`won_or_sold / total_transactions`) kapsayacak şekilde güncellenmesi.
- [x] **1.3. Güvenlik ve Hata Kotrolü (Error Handling & Edge Cases)**
  - [x] Sıfıra bölünme (`total == 0`) ve null değer kontrollerinin teyit edilmesi.
  - [x] Redis `seller:badge:{uid}` yazma boru hattının (pipeline) ve 25 saatlik TTL değerinin korunmasının doğrulanması.

---

## 🔗 Faz 2: Trend Rozeti Sunum Katmanı Birleşimi (`listing_utils.py`)
- [ ] **2.1. Redis Pipeline Okumasının Güncellenmesi**
  - [ ] `backend/app/use_cases/listings/queries/listing_utils.py` dosyasındaki `_fetch_seller_meta()` fonksiyonunun incelenmesi.
  - [ ] `trending:listings` (6 saatlik yavaş küme) ile `trending:listings:velocity` (30 dakikalık hızlı küme) anahtarlarının Redis'ten tek bir pipeline veya `mget`/multi-set sorgusu ile eşzamanlı çekilmesi.
- [ ] **2.2. Küme Birleşimi (`UNION`) İşleminin Uygulanması**
  - [ ] Çekilen iki kümenin Python bellek seviyesinde birleşiminin (`set_slow | set_fast`) alınarak `trending_listing_ids` değişkenine atanması.
- [ ] **2.3. Bağımlı Servislerin Etki Analizi**
  - [ ] `GetListingQuery` (İlan Detay), `GetMyListingsQuery` (Profil İlanları) ve arama uç noktalarının birleşik trend kümesini doğru tükettiğinin kontrol edilmesi.

---

## 🧪 Faz 3: Otomatize Doğrulama ve Test Scriptleri
- [x] **3.1. Satıcı Rozeti Test Scripti (`test_seller_badges_exhaustive.py`)**
  - [x] Normal (hemen al / teklif) ilan satışı yapmış ancak hiç açık artırma açmamış örnek (mock) satıcı verisi oluşturan script yazılması.
  - [x] Scriptin `compute_seller_badges_task` fonksiyonunu tetikledikten sonra Redis'te `trusted_seller` / `active_seller` rozetinin oluştuğunu doğrulaması.
- [x] **3.2. Trend Tutarlılık Test Scripti (`test_trending_consistency.py`)**
  - [x] Sadece `trending:listings:velocity` kümesinde yer alan bir ilan ID'sinin simüle edilmesi.
  - [x] `listing_utils._fetch_seller_meta()` ve `_row_dict()` fonksiyonları çağrıldığında `is_trending` değerinin `True` döndüğünün programmatik olarak teyit edilmesi.

---

## 🚀 Faz 4: VPS Canlı Dağıtım ve İzleme (Staging & Deployment)
- [ ] **4.1. Git Commit ve Deploys**
  - [ ] Yapılan tüm modernizasyonların lokalde test edilmesi ve GitHub `main` dalına push edilmesi.
  - [ ] VPS sunucusunda `git pull` yapılması ve backend servislerinin (`sudo systemctl restart teqlif` / celery worker) yeniden başlatılması.
- [ ] **4.2. Log ve Metrik Gözlemi**
  - [ ] Gece 01:30 cron görevinin (veya manuel tetiklenen test koşusunun) worker loglarındaki `"rozet=X"` çıktısının izlenmesi ve rozet alan satıcı sayısındaki adil artışın gözlemlenmesi.
  - [ ] Mobil uygulama üzerinden Keşfet akışı ile İlan Detay sayfaları arasındaki 🔥 Trend rozeti görsel tutarlılığının canlı test edilmesi.
