# Pro Araçları (Pro Tools) Mikro Segmentasyon ve Veri Zenginleştirme Planı

Bu belge, Teqlif platformundaki Pro Araçları'nın (Analitikler, Fiyat Radarı, Talep Trendleri vb.) makro düzeyden (sadece kategori/alt-kategori bazlı) çıkıp, mikro düzeye (Marka, Model, Şehir, Durum vb. `extra_fields` bazlı) genişletilmesi için gereken veri mimarisi planını içermektedir.

Mevcut VPS kapasitesi (24 GB RAM, 6 vCPU, 100 GB SSD) nedeniyle bu plan, sunucu donanımı büyütüldüğünde devreye alınmak üzere dondurulmuştur.

---

## 1. Neden Ertelendi? (Sistem Maliyeti ve VPS Darboğazı)

Pro Araçlarının altyapısı **ClickHouse** tabanlıdır. ClickHouse, sütun odaklı (columnar) ve çok hızlı bir veritabanı olmasına rağmen, JSON veya dinamik yapıdaki "sonsuz parametreleri" (extra_fields) işlemesi maliyetlidir.

Eğer tüm `extra_fields` verisi ClickHouse'a dinamik bir JSON veya String Map olarak gömülseydi:
- **İşlemci (CPU) Darboğazı:** `JSONExtractString` veya Map tarama işlemleri sorgu sırasında (runtime) parse gerektirdiğinden 6 vCPU hızla %100 kullanıma ulaşır.
- **Disk (SSD) Tüketimi:** Her bir tıklama ve görüntüleme olayına tam bir JSON metadata basmak, ClickHouse'un veri sıkıştırma avantajını bitirir ve 100 GB SSD'yi çok hızlı doldururdu.
- **RAM Darboğazı:** Dinamik string aramaları ve gruplamaları agresif RAM kullanır, artan eşzamanlı satıcı kullanımında OOM (Out Of Memory) hataları riskini doğurur.

---

## 2. Gelecekteki İdeal Mimari Çözümü (The ClickHouse Way)

Platform daha büyük bir donanıma geçtiğinde bile "Sonsuz Parametre (Raw JSON)" basmak mimari olarak yanlıştır. Bunun yerine en çok talep edilen stratejik boyutlar belirlenip sabit kolon olarak eklenmelidir.

### Önerilen Şema Değişikliği (Dictionary & LowCardinality)
Piyasanın en çok aradığı filtreler (örneğin 5-6 adet) belirlenecek ve ClickHouse'daki tablolarına (`user_events`, `feed_analytics`, `swipe_live_events`) `LowCardinality(String)` olarak eklenecektir.

```sql
ALTER TABLE user_events ADD COLUMN IF NOT EXISTS city LowCardinality(String) DEFAULT '';
ALTER TABLE user_events ADD COLUMN IF NOT EXISTS brand LowCardinality(String) DEFAULT '';
ALTER TABLE user_events ADD COLUMN IF NOT EXISTS model_name LowCardinality(String) DEFAULT '';
ALTER TABLE user_events ADD COLUMN IF NOT EXISTS condition LowCardinality(String) DEFAULT '';
```
*Not: LowCardinality kullanımı, string verileri ID'lere (dictionary) çevirerek inanılmaz disk sıkıştırması sağlar ve CPU maliyetini neredeyse sıfıra indirir.*

---

## 3. Uçtan Uca (E2E) Uygulama Adımları

Daha güçlü bir sunucuya geçildiğinde yapılacak teknik geliştirmeler:

### Adım 1: ClickHouse Şema Güncellemeleri
- `backend/app/database_clickhouse.py` içindeki DDL tanımları güncellenecek.
- Yeni `city`, `brand`, `condition` vb. kolonlar `LowCardinality` tipiyle eklenecek.

### Adım 2: Backend Event Ingestion (Veri Toplama)
- `/api/analytics/track` vb. endpointler bu yeni parametreleri alacak.
- Mobile veya web istemcisi, kullanıcının incelediği ilanın detaylarını (şehir, marka) bu event payload'una dahil edecek. 
*(Backend'in Redis üzerinden ID ile arama yapması yerine, veriyi frontend'in event içine koyarak göndermesi sunucu yükünü azaltacaktır).*

### Adım 3: Backend Read API (Pro Araçları Sorguları)
- `backend/app/routers/analytics.py` ve `listings.py` içindeki Read (grafik çizen) endpoint'ler Query Params olarak bu yeni filtreleri kabul edecek.
- ClickHouse'a giden `SELECT` sorgularının `WHERE` koşullarına (ör: `WHERE city = :city AND brand = :brand`) dinamik olarak eklenecek.

### Adım 4: Mobile UI ve API Servisleri
- Mobile uygulamasındaki (`competitor_radar_screen.dart`, `demand_trends_screen.dart` vb.) gizlenen ekstra alanlar (`showExtraFields: true`, `showCity: true`) aktif edilecek.
- `mobile/lib/services/analytics_service.dart` üzerinden yapılan isteklerde `TeqFilterBar`'dan alınan dinamik parametreler URL query parametresi (`?city=Istanbul&brand=Apple`) olarak backend'e iletilecek.

---

## Sonuç

Bu genişletme yapıldığında satıcılar; *"Sadece Ankara'daki, İkinci El, Apple marka telefonların talep trendi"* veya *"Otomatik vites dizel araçların rekabet radarındaki ortalama fiyatı"* gibi mikro segmentasyon verilerine anlık ve ışık hızında ulaşabilecektir.
