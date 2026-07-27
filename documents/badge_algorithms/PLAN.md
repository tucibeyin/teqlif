# 🏆 Teqlif Rozet Algoritmaları (Badge Algorithms) - Mimari Modernizasyon Planı

## 1. Yönetsel Özet ve Bağlam (Executive Summary & Background)
Teqlif platformunda ilan kartları üzerinde gösterilen satıcı rozetleri (`trusted_seller`, `active_seller`) ve trend ilan rozeti (`is_trending`), kullanıcı güvenini tesis etmek ve etkileşimi artırmak amacıyla tasarlanmıştır. Ancak mevcut sistemde yapılan mimari incelemeler sonucunda, rozet algoritmalarının **iki önemli alanda endüstri standartlarından ve pazaryeri esnekliğinden saptığı** tespit edilmiştir:

1. **Alan Modellemesi Sızıntısı (Domain Leakage - Açık Artırma Körlüğü):** Satıcı rozetlerini hesaplayan arka plan işçisi (`compute_seller_badges_task`), yalnızca SwipeLive canlı yayın/açık artırma modülüne ait `auction_won` ve `auction_ended` etkinliklerini saymaktadır. Bu durum, platformdaki normal doğrudan satış (Hemen Al / Teklif Usulü) yapan başarılı satıcıların sistem tarafından yok sayılmasına yol açmaktadır.
2. **Görsel Sunum Tutarsızlığı (Visual Presentation Mismatch - Trend Rozeti):** Keşfet (Anasayfa) akışı 30 dakikalık yüksek hızlı trend kümesini (`trending:listings:velocity`) kullanırken; Arama, Satıcı Profili ve İlan Detay sayfaları 6 saatlik yavaş trend kümesini (`trending:listings`) okumaktadır. Bu durum, bir ilanın Keşfet ekranında 🔥 rozetine sahipken, detayına girildiğinde veya aramalarda rozetin kaybolmasına neden olmaktadır.

Bu döküman, söz konusu algoritmaları **eBay, Airbnb, MercadoLibre ve TikTok/Twitter** gibi küresel endüstri devlerinin standartlarına uygun şekilde olgunlaştırmak için tasarlanmış mimari modernizasyon planıdır.

---

## 2. Endüstri Standartları ve Mimari Gerekçeler (Industry Standards Justification)

### 2.1. Satıcı Rozetlerinde Çoklu Ticaret Modeli (Multi-Format Commerce)
* **Kurumsal Standart (eBay Top Rated Seller / Airbnb Superhost):** Küresel pazaryerlerinde satıcı kademeleri (tiering), satıcının yalnızca tek bir satış kanalındaki değil, platform üzerindeki **tüm işlem biçimlerindeki (açık artırma, sabit fiyat, teklif kabulü)** hacmine, iptal oranına ve müşteri memnuniyetine göre hesaplanır.
* **Teqlif Mimarisine Uygulanması:** `user_events` tablosunda ve PostgreSQL üzerindeki işlem geçmişinde yer alan normal satış/teklif kabulü etkinlikleri (Örn: `offer_accepted`, `listing_sold`, `order_completed`), `auction_won` ile eşdeğer bir başarı kriteri olarak algoritmaya dahil edilecektir.
* **Batch Zamanlaması Doğrulaması:** Satıcı güven skorlarının ve rozetlerinin anlık (real-time) yerine **günde 1 kez (Gece 01:30 cron) hesaplanması ve 25 saat TTL ile Redis'te tutulması endüstri standardıdır.** Bu tasarım, anlık iptal/iade dalgalanmalarının satıcı rozetinde manipülatif yanıp sönmelere yol açmasını engeller ve veritabanı performansını korur.

### 2.2. Trend Rozetinde Sunum Katmanı Birleşimi (Presentation Layer Union)
* **Kurumsal Standart (TikTok / Reddit / HackerNews):** Keşfet/Viral akışlar (Discovery Feed), taze ve ani sıçrama yapan içerikleri yakalamak için kısa vadeli hız (velocity / EWMA) modelleri kullanır. Arama ve Katalog sayfaları ise spam manipülasyonunu önlemek için uzun vadeli stabil modeller kullanır.
* **Teqlif Mimarisine Uygulanması:** Sıralama (ranking) algoritmalarının zaman ufuklarına dokunulmayacaktır (Keşfet 30 dk, Arama 6 saat olarak kalmalıdır). Ancak **Görsel Rozet Sunumu (`is_trending` bayrağı)** hesaplanırken, API sunum katmanında (`listing_utils.py`) iki kümenin birleşimi (`UNION`) alınacaktır. Böylece bir ilan platformun herhangi bir algoritmasında trend girdiyse, arayüzün tüm ekranlarında tutarlı bir şekilde 🔥 rozetiyle sergilenecektir.

---

## 3. Mevcut Durum vs. Önerilen Mimarinin Karşılaştırılması (Current vs. Proposed Architecture)

| Bileşen / Katman | Mevcut Durum (Current State) | Önerilen Kurumsal Mimari (Proposed Architecture) | Kazanç / Beklenen Fayda |
| :--- | :--- | :--- | :--- |
| **Satıcı Rozet Algoritması**<br>`worker.py:L2298` | Sadece `auction_won` ve `auction_ended` etkinliklerini sayar. Normal ilan satan satıcılar rozet alamaz. | ClickHouse sorgusuna `offer_accepted`, `listing_sold`, `order_completed` etkinlikleri ve PostgreSQL işlem teyidi eklenir. | Tüm pazaryeri satıcıları için %100 adil ve kapsayıcı rozet dağılımı. |
| **Trend Rozet Sunumu**<br>`listing_utils.py:L51` | Yalnızca `trending:listings` (6 saatlik yavaş küme) okunur. Keşfet akışı ile aralarında rozet uyuşmazlığı vardır. | Redis okumasında `trending:listings` ile `trending:listings:velocity` kümeleri birleştirilir (`UNION` veya `mget`). | Sayfalar (Keşfet vs Arama vs Detay) arasında %100 görsel rozet tutarlılığı. |
| **Performans Maliyeti** | Redis'ten tek küme okuma (~0.2 ms). | Redis pipeline ile iki küme okuma ve küme birleşimi (<0.4 ms). | Sıfıra yakın gecikme (latency), maksimum mimari tutarlılık. |

---

## 4. Teknik Uygulama Planı (Detailed Implementation Blueprint)

### 4.1. Satıcı Rozeti Kapsamının Genişletilmesi (`backend/app/worker.py`)
1. **ClickHouse Sorgu Revizyonu (`compute_seller_badges_task`):**
   * Mevcut sorgudaki `WHERE event_type IN ('auction_won', 'auction_ended')` filtresi genişletilecek:
     ```sql
     WHERE event_type IN (
         'auction_won', 'auction_ended', 
         'offer_accepted', 'listing_sold', 'order_completed'
     )
     ```
   * Dönüşüm oranı (conversion rate) hesabı: `won_or_sold / total_transactions` olarak yeniden formüle edilecek.
2. **Dinamik Eşik (Threshold) Korunması:**
   * 75. yüzdelik dilim (`p75_conv`) ve medyan (`p50_total`) dinamik eşik hesaplama mantığı korunacak, böylece platform büyüdükçe rozet zorluk derecesi otomatik dengelenecek.

### 4.2. Trend Rozeti Sunum Katmanı Birleşimi (`backend/app/use_cases/listings/queries/listing_utils.py`)
1. **Redis Okuma Genişletmesi (`_fetch_seller_meta`):**
   * Mevcut `trending_listing_ids` küme okuması revize edilecek:
     ```python
     # Hem 6 saatlik stabil trendleri hem 30 dakikalık hızlı velocity trendlerini oku
     t_slow, t_fast = await redis.pipeline() \
         .smembers("trending:listings") \
         .smembers("trending:listings:velocity") \
         .execute()
     
     trending_listing_ids = {int(v) for v in (t_slow or set())} | {int(v) for v in (t_fast or set())}
     ```
2. **API Dönüş Formatı (`_row_dict`):**
   * `is_trending` alanı artık ilanın bu birleşik kümede bulunma durumuna göre `True/False` dönecek.

---

## 5. Doğrulama ve Test Planı (Verification & Testing Plan)

### 5.1. Otomatize / Script Testleri
* **Satıcı Rozeti Doğrulama Scripti:** `scripts/test_seller_badges_exhaustive.py` oluşturularak hiç açık artırma açmamış ancak 10 adet normal satış yapmış sahte (mock) bir satıcının `compute_seller_badges_task` çalıştırıldıktan sonra `trusted_seller` rozeti aldığı test edilecek.
* **Trend Rozeti Tutarlılık Scripti:** `scripts/test_trending_consistency.py` oluşturularak `trending:listings:velocity` kümesinde olup `trending:listings` kümesinde olmayan bir ilanın, `GetListingQuery` ve `GetMyListingsQuery` servislerinde `is_trending: True` döndürdüğü doğrulanacak.

### 5.2. VPS Staging & Canlı Doğrulama
* VPS üzerinde `compute_seller_badges_task` tetiklenerek Redis üzerindeki `seller:badge:*` anahtarlarının sayısı ve dağılımı loglanacak.
* Mobil uygulama üzerinden Keşfet akışındaki 🔥 rozetli bir ilanın detayına girilerek rozetin detay sayfasında ve arama sonuçlarında tutarlı şekilde kaldığı görsel olarak teyit edilecek.
