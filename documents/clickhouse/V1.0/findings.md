# ClickHouse V1.0 - Optimizasyon ve Darboğaz Keşifleri (Findings)

Bu doküman, ClickHouse altyapısının 10.000 (ve ileride 50.000) anlık kullanıcıyı (CCU) sorunsuz şekilde kaldırabilmesi, disk şişmelerinin önlenmesi ve yüksek CPU kullanımının düşürülmesi amacıyla yapılan keşifleri ve kod tabanına uygulanan kalıcı çözümleri listeler.

## 1. Veri Tipi ve Depolama (Storage) İyileştirmeleri
* **ZSTD Codec Sıkıştırması:** ClickHouse varsayılan olarak LZ4 kullanmaktadır. Disk ayak izini dramatik şekilde küçültmek amacıyla tüm tekrarlayan veri tiplerine (String, LowCardinality, UInt vb.) `CODEC(ZSTD(3))` uygulandı. Bu adım, aynı veriyi diske %40-50 daha az alan kaplayacak şekilde yazdırır.
* **String'den UInt32'ye Geçiş:** `feed_analytics` tablosundaki `user_id` ve `listing_id` sütunları `String`'den `UInt32`'ye geçirildi. Backend'de API rotaları ve servisler (ML, Analytics, Recommendations) string kullanmak yerine integer üzerinden işlem yapacak şekilde (parse/cast) optimize edildi.
* **Nullable Tipi Problemi:** ClickHouse'da `Nullable` tiplerin arka planda oluşturduğu maske dosyası nedeniyle performans kaybı yaşattığı keşfedildi. `user_events` tablosundaki `user_id Nullable(UInt32)` alanı iptal edilerek yerine `UInt32 DEFAULT 0` yapısına geçildi (0, anonim/bilinmeyen kullanıcı olarak değerlendirilir).

## 2. Dizinleme (Indexing) ve Sorgu Optimizasyonları
* **Bloom Filter İndex:** `hot_leads` ve `pro_insights` sorgularında sürekli belirli `item_id` grupları üzerinden arama yapıldığı tespit edildi. `user_events` tablosuna `INDEX idx_item_id item_id TYPE bloom_filter GRANULARITY 1` eklenerek tablo tam tarama (full-scan) zahmetinden kurtarıldı.
* **Sıralama (ORDER BY) İyileştirmesi:** `feed_analytics` tablosunun `ORDER BY` tanımı veri okuma pratiklerine daha uygun olması için `(user_id, timestamp)` şeklinde güncellendi.
* **Materialized View ile Ön-Toplama:** Pro satıcı paneli her yüklendiğinde milyonlarca tıklama olayının (`user_events`) canlı olarak toplanması (count) CPU'ya aşırı yük bindiriyordu. Bunu engellemek için arka planda anlık çalışan `mv_listing_events_daily` (`AggregatingMergeTree`) tasarlandı. Günlük olarak `views`, `dwells` ve `hesitating_users` verisini önceden toplayan bu tablo sayesinde sorgular milisaniye seviyesine indirildi.

## 3. Sistem Kaynak Tüketimi (CPU & Bellek) Ayarları
* **Flush ve MergeTree CPU Yükü:** FastAPI asenkron worker'larının ClickHouse'a her 5 saniyede bir veri gömmesinin (Flush), CH'un disk üzerinde sürekli partisyon oluşturmasına ve bu dosyaları birleştirmek (merge) için devasa CPU tüketmesine yol açtığı fark edildi. `FLUSH_INTERVAL` 30 saniyeye ve `MAX_BATCH` limiti 2000'den 5000'e çıkarılarak arka plandaki I/O yükü 6 kat hafifletildi.
* **OOM (Out-of-Memory) Koruması:** `node_core_limits.xml` konfigürasyonu üzerinden ML eğitim ve BPR modelleri sırasında RAM'in aşırı tüketilmesini engellemek için `max_memory_usage` limitleri (ör. 1.5 GB / sorgu) tanımlandı. Aşım durumunda bellek yerine diske spill etmesi sağlandı.

## 4. Agresif Veri Silme (TTL) Politikaları
Devasa disk büyümesinin ana nedeni uzun ömürlü Time-To-Live yapılarıydı. ML algoritmalarının ihtiyaç duyduğu zaman dilimleri hesaplanarak gereksiz depolamalar budandı:
* `user_events`: 180 gün → 30 güne düşürüldü.
* `feed_analytics`: 365 gün → 30 güne düşürüldü.
* `swipe_live_events`: 180 gün → 30 güne düşürüldü.
* `direct_sale_events`: 730 gün → 180 güne düşürüldü. 

Bu sayede 25 GB'lık NVMe diskin 10,000+ kullanıcıda dahi %100 doluluğa ulaşması engellenmiştir.
