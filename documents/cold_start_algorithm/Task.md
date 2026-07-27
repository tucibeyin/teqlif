# 📋 Teqlif Tavsiye Motoru & Cold Start Geliştirme Görev Listesi (Task.md)

Bu görev listesi, [Plan.md](file:///Users/tucibeyin/Desktop/teqlif/documents/cold_start_algorithm/Plan.md) dokümanında belirlenen mimari hedefleri gerçekleştirmek üzere adım adım uygulanacak teknik maddeleri içerir.

---

## 🏗️ Faz 1: Algoritma ve Kural Tabanlı Fallback Güncellemeleri (`backend/app/use_cases/feed/`)

- [x] **1.1. `_popular_feed()` SQL Sorgusunun Modernize Edilmesi**
  - Dosya: [feed_queries.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/feed/queries/feed_queries.py)
  - İşlem: Sadece beğeni sayısına (`COUNT(ll.id)`) ve tarihe (`l.created_at`) bakan eski sıralama kaldırılarak, ilan kalite skoru (`quality_score`) ve satıcı güven skorunu harmanlayan çok faktörlü formüle geçilecek.
  - Formül: `ORDER BY (COUNT(ll.id) * 1.5 + COALESCE(l.quality_score, 0.5) * 4.0) DESC, l.created_at DESC`
  - Doğrulama: Beğenisi 0 olan ilanlarda sıralamanın `quality_score` yüksek olanları üste taşıdığının test edilmesi.

- [x] **1.2. Zero-Latency In-Session Semantic Re-ranking (Anlık Oturum Drift Fallback)**
  - Dosya: [feed_queries.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/feed/queries/feed_queries.py)
  - İşlem: `_compute_foryou_ids` metodu içinde, kullanıcının veritabanında `preference_embedding` değeri NULL olsa bile, oturum içinde tıkladığı son ilanlardan (`feed:signal` session vektöründen) bir başlangıç vektörü alınıp semantik aramanın (`pgvector`) anında tetiklenmesi sağlanacak.

---

## 🤖 Faz 2: ML & ClickHouse ALS Optimizasyonları (`backend/app/services/ml/`)

- [x] **2.1. ALS Eğitim Eşik Değerinin (`_MIN_ROWS`) Düşürülmesi**
  - Dosya: [feed_als_ml.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/feed_als_ml.py)
  - İşlem: Erken beta ve geliştirme ortamlarının dinamiklerine uygun olarak `_MIN_ROWS = 50` barajı `_MIN_ROWS = 15` seviyesine indirilecek.

- [x] **2.2. ALS Güven Skoru Ağırlıklarının İnce Ayarı**
  - Dosya: [feed_als_ml.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/feed_als_ml.py)
  - İşlem: Seyrek matrislerde (sparse matrix) `bid_hesitation` (teklif tereddütü) ve `long_dwells` (uzun süreli inceleme) sinyallerinin model öğrenmesindeki etkisi optimize edilecek.

---

## 🛠️ Faz 3: Test & Geliştirici Araçları (`backend/scripts/`)

- [x] **3.1. Manuel ALS ve Feed Ön Bellek Yönetim Scriptinin Yazılması**
  - Dosya: [trigger_feed_ml.py](file:///Users/tucibeyin/Desktop/teqlif/backend/scripts/trigger_feed_ml.py) (Yeni Dosya)
  - İşlem: Gece 03:45'i beklemeden terminalden `python3 scripts/trigger_feed_ml.py` komutuyla ClickHouse verisinden ALS eğitimini anında başlatan ve Redis önbelleğini (`feed:foryou:*`, `feed:als:*`) invalid eden CLI aracı oluşturulacak.

---

## 🧪 Faz 4: Doğrulama ve Raporlama

- [x] **4.1. Ayrışma (Divergence) Testi**
  - İşlem: Aynı kullanıcı ile `/feed/recent` (Son İlanlar) ve `/feed/for-you` (Keşfet) uç noktalarına paralel istek atılıp, dönen ilan listelerinin artık birebir aynı olmadığı teyit edilecek.
- [x] **4.2. Yürüyüş Raporu (Walkthrough) ile Tamamlama**
  - İşlem: Yapılan tüm geliştirmeler, test çıktıları ve loglar bir araya getirilerek kullanıcıya sunulacak.
