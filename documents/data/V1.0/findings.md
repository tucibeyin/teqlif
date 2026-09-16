# Veritabanı ve Mimari Optimizasyon Analizi (Bulgular)

Bu doküman, sistemin PostgreSQL, Redis ve ClickHouse katmanlarındaki durumunu analiz eder ve ileride (örn. 10.000+ anlık kullanıcı) yapılması gereken endüstri standartlarındaki iyileştirmeleri not düşer.

## 1. PostgreSQL (Transactional DB) Optimizasyonları

### 1.1. BigInteger (Int8) PK Migrasyonu
Mevcut durumda `Mapped[int]` deklarasyonu varsayılan olarak 4-byte `Integer` oluşturmaktadır (Max kapasite: 2,147,483,647). 
- **Risk Altındaki Tablolar:** `direct_messages`, `notifications`, `listing_impressions`, `story_views`. Günde milyonlarca satır üreten bu tablolar kapasiteyi doldurabilir.
- **Çözüm:** İleride bu tabloların `id` alanlarının ve bu tablolara referans veren Foreign Key'lerin `BigInteger` tipine çevrilmesi. (Dikkat: Kilitlenmelere karşı maintenance gerektirir.)

### 1.2. Sohbet (Mesajlaşma) İndeks Optimizasyonu
- **Mevcut Durum:** `direct_messages` tablosunda `(sender_id, receiver_id, created_at)` indeksi bulunuyor.
- **Sorun:** İki kişi arasındaki geçmişi çeken "A-B veya B-A" sorgusu `OR` kullandığı için index'i zayıf kullanır.
- **Çözüm:** Mesaj tablosuna `conversation_id` (örn. `A_B` sıralı) eklenip tek bir eşitlik kontrolü ile indeksin %100 randımanlı çalıştırılması.

### 1.3. Tablo Bölümleme (Table Partitioning)
- `direct_messages` ve `notifications` logludur. İlerleyen günlerde aylık/haftalık partition'lara bölünmeleri performansı stabil tutacaktır.

## 2. Redis (Caching & Pub/Sub) Optimizasyonları

### 2.1. Pub/Sub Yerine Redis Streams (Dayanıklı Mesajlaşma)
- **Sorun:** Mevcut sohbet WS altyapısında `Redis Pub/Sub` kullanılıyor. Kullanıcı tünelden geçerken anlık koparsa o sıradaki mesajlar delivery garantisi olmadığı için kaybolur (WebSocket reconnet olana dek).
- **Çözüm:** Pub/Sub yerine **Redis Streams** (`XADD`, `XREAD`) kullanılarak her client'ın kendi `last_id` imlecini tutması.

### 2.2. Connection Pool Darboğazı
- 10K CCU için `max_connections=50` yetersiz kalabilir. Pool size donanıma göre artırılmalı veya Redis Cluster desteği kod bazında eklenmeli.

## 3. ClickHouse (Analytics DB) İleri Düzey Optimizasyonları

(Aşama 2'de TTL, ZSTD, Bloom Filter, Batch tuning vb. yapılmıştır. Aşağıdakiler ek iyileştirmelerdir):

### 3.1. Dictionary Kullanımı
- Kategoriler ve subkategoriler için `LowCardinality(String)` yerine ClickHouse **Dictionaries** tanımlanarak PostgreSQL'den bellek içi (in-memory) lookup yapılması ve string yerine `UInt8` depolanması. (Sorgu hızını çok ciddi katlar).

### 3.2. Real-Time Materialized Views
- Sık sorulan "Bugün Kaç Gösterim Aldım" gibi sorgular için ana tabloları yormak yerine arka planda çalışan `AggregatingMergeTree` kullanan bir `Materialized View` oluşturulması.
