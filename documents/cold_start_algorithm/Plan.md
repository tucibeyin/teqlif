# 🚀 Teqlif "Sana Özel (For-You)" & Cold Start Tavsiye Motoru Mimarisi

Bu doküman, Keşfet sayfasındaki **"Sizin İçin Seçilen İlanlar" (For-You Feed)** ile İlanlar sayfasındaki **"Son İlanlar" (Recent Feed)** akışlarının aynı ilan listesini göstermesi sorununu kökten çözmek ve Teqlif tavsiye motorunu endüstri standartlarına (TikTok, Vinted, Airbnb) taşımak için hazırlanan uçtan uca mimari dönüşüm planıdır.

---

## 1. 🔍 Mevcut Durum Analizi ve Kök Nedenler

Yapılan teknik incelemede aşağıdaki 3 temel kök neden tespit edilmiştir:

1. **Cold Start (Soğuk Başlangıç) Çöküşü:** 
   `FeedQueries.get_foryou_feed` metodu, kullanıcının veritabanında `preference_embedding` (ilgi vektörü) bulunmadığında veya K-Means onboarding vektörü üretilemediğinde `_popular_feed()` metoduna fallback yapmaktadır.
2. **Beğeni Sayısı (Like Count) Düğümü:** 
   `_popular_feed()` sorgusu `ORDER BY COUNT(ll.id) DESC, l.created_at DESC` kuralıyla çalışmaktadır. Test, beta veya yeni canlı ortamlarında ilanların beğeni sayıları `0` olduğunda sorgu otomatik olarak **`ORDER BY l.created_at DESC`** (en yeniden en eskiye) sıralamasına dönüşmekte; bu da Son İlanlar (`/feed/recent`) ile %100 aynı listeyi üretmektedir.
3. **ALS (Collaborative Filtering) 50 Satır Barajı:** 
   ClickHouse üzerindeki (`feed_analytics`, `user_events`) verilerini işleyip matris ayrıştırması (ALS) yapan `train_feed_als` gece 03:45'te batch çalışmakta ve en az 50 geçerli etkileşim (`_MIN_ROWS = 50`) olmadığı sürece modeli eğitmeyi reddetmektedir.

---

## 2. 🏆 Endüstri Standartlarına Hedeflenen Dönüşüm

| Özellik / Katman | Mevcut Teqlif Mimarisi | Endüstri Standardı (TikTok / Vinted / Airbnb) | Hedeflenen Teqlif Çözümü |
| :--- | :--- | :--- | :--- |
| **Cold Start (Sıfır Etkileşim)** | Sadece Beğeni Sayısı + Tarih (`created_at DESC`). | Çok Faktörlü Kalite Vitrini (Bayesian Ranking, Güven Skoru, CTR Velocity). | İlan Kalite Skoru (`quality_score`), Satıcı Güveni (`trust_score`) ve Trend rozetleriyle harmanlanan Akıllı Vitrin. |
| **ALS Eğitim Barajı** | Sabit 50 satır (`_MIN_ROWS = 50`). Gece 03:45 batch döngüsü. | Erken aşamada düşük baraj (10-15 satır), adaptif öğrenme ve anlık fallback. | Barajın `15` satıra çekilmesi, geliştirme/test ortamları için anlık CLI tetikleyici eklenmesi. |
| **Oturum İçi (In-Session) Drift** | 30 dk Redis session vektörü var ancak DB embedding yoksa fallback baskın geliyor. | İlk tıklamada Zero-Latency semantik kırılma (Son tıklanan ilana göre anlık k-NN). | `preference_embedding` NULL olsa bile son tıklanan ilanın embedding'ini geçici oturum vektörü yapıp anında re-ranking. |
| **Önbellek (Cache TTL)** | Sabit 15 dakika (`FORYOU_CACHE_TTL = 900`). | Etkileşim olduğu an invalidated veya incremental update edilen önbellek. | Etkileşim sinyali (`/feed/signal`) geldiğinde veya test sırasında önbelleği esnek yönetme imkanı. |

---

## 3. 🛠️ Önerilen Mimari Değişiklikler

Değişiklikler bileşen bazlı olarak aşağıda gruplandırılmıştır:

### 3.1. Backend Query & Algoritma Katmanı (`backend/app/use_cases/feed/`)

#### [MODIFY] [feed_queries.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/feed/queries/feed_queries.py)
- **`_popular_feed()` Sorgusunun Modernizasyonu:**
  Mevcut sadece beğeni ve tarihe bakan sıralama değiştirilerek, ilanların kural ve ML tabanlı kalite skoru (`quality_score`), satıcının güven skoru (`users.trust_score`) ve beğeni sayısını harmanlayan çok faktörlü bir formüle geçirilecek:
  $$\text{Ranking Score} = (\text{COALESCE}(l.quality\_score, 0.5) \times 4.0) + (\text{COUNT}(ll.id) \times 1.5) + (\text{Freshness Decay})$$
  *Böylece hiç beğeni olmasa dahi vitrin kalitesi en yüksek ilanlar Keşfet'in en üstünde yer alacak.*
- **Zero-Latency In-Session Semantic Re-ranking:**
  `_compute_foryou_ids` içinde `user.preference_embedding` NULL olsa bile, kullanıcının o oturumda tıkladığı son ilanlardan (`feed:signal` session drift vektöründen) bir başlangıç vektörü oluşturularak semantik arama anında tetiklenecek.

### 3.2. ML & ClickHouse Katmanı (`backend/app/services/ml/`)

#### [MODIFY] [feed_als_ml.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/feed_als_ml.py)
- **Eşik Değeri (Threshold) Optimizasyonu:**
  `_MIN_ROWS = 50` barajı, erken dönem platform dinamiklerine ve test süreçlerine uyum sağlaması için `_MIN_ROWS = 15` seviyesine çekilecek.
- **Güven Ağırlıklarının (Confidence Weights) İnce Ayarı:**
  `bid_hesitation` (teklif tereddütü, çarpan: 2.0) ve uzun süreli inceleme (`long_dwells`, çarpan: 0.7) sinyallerinin ALS matrisindeki seyreklik (sparsity) toleransı artırılacak.

### 3.3. Test & Geliştirici Araçları Katmanı (`backend/scripts/`)

#### [NEW] [trigger_feed_ml.py](file:///Users/tucibeyin/Desktop/teqlif/backend/scripts/trigger_feed_ml.py)
- Geliştirici ve QA ekiplerinin gece saat 03:45'i beklemeden terminal üzerinden tek satırla ClickHouse'taki mevcut veriler üzerinden ALS eğitimini başlatabileceği, Redis önbelleklerini (`feed:foryou:*`, `feed:als:*`) temizleyebileceği bir yönetim scripti oluşturulacak.

---

## 4. ⚠️ Kullanıcı ve Mimari Onayı Gerektiren Noktalar (User Review Required)

> [!IMPORTANT]
> **Sıralama Davranış Değişikliği:** Yapılacak bu geliştirmeden sonra yeni bir misafir veya üye Keşfet sekmesini açtığında artık en son eklenen ilanları değil; fotoğrafları en kaliteli, eksiksiz doldurulmuş ve kaliteli satıcılara ait ilanları görecektir. En son eklenen ilanlar ise olması gerektiği gibi sadece **İlanlar -> Son İlanlar** sekmesinde listelenecektir.

> [!TIP]
> **Performans Etkisi:** `_popular_feed()` içinde `COALESCE(l.quality_score, 0.5)` kullanımı, veritabanında zaten var olan `quality_score` (b-tree indeksli) sütununu okuyacağı için sorgu süresine ekstra bir gecikme eklemez (~2-5ms bandında kalır).

---

## 5. 🧪 Doğrulama ve Test Planı (Verification Plan)

Değişikliklerin başarısı aşağıdaki adımlarla doğrulanacaktır:

### 5.1. Otomatik ve Script Bazlı Testler
1. **Sorgu Farklılığı Testi:** Hem `/feed/recent` hem de `/feed/for-you` uç noktalarına istek atılıp dönen ilan ID listelerinin kesişim kümesinin %100 olmadığı (farklılaştığı) programatik olarak doğrulanacak.
2. **ALS Baraj ve Eğitim Testi:** Yeni oluşturulacak `python3 scripts/trigger_feed_ml.py --force` komutu çalıştırılarak ClickHouse verisi üzerinden modelin 15+ satırla başarıyla eğitildiği ve Redis'e vektör yazdığı loglanacak.

### 5.2. Manuel Doğrulama Adımları
1. Mobil uygulama üzerinden sıfır kilometre bir hesapla giriş yapılacak.
2. **İlanlar** sekmesinde kronolojik akışın geldiği, **Keşfet** sekmesinde ise görsel kalitesi yüksek (quality_score yüksek) vitrin ilanlarının en üstte yer aldığı canlı olarak gözlemlenecek.
3. Keşfet'ten spesifik bir kategoriye (örn: Otomobil) ait bir ilana tıklanıp 5 saniye incelenecek. Keşfet yenilendiğinde anlık session drift sayesinde benzer araçların listenin üst sıralarına yükseldiği teyit edilecek.
