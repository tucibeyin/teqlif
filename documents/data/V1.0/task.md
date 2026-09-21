# teqlif — Task Listesi

**Plan:** `documents/data/V1.0/plan.md`  
**Mimari:** `documents/teqlif_architectural_decisions.md`  
**Prensipler:** Clean Architecture (Router → Use Case → Repository) · Clean Code · MVVM (Flutter)

---

## Workflow (Her Task İçin)

```
1. Uygula         — kodu yaz, migration/config değişikliklerini hazırla
2. Review onayı   — kullanıcı kodu inceler, "onaylıyorum" der
3. Test onayı     — kullanıcı staging/local'de test eder, "test geçti" der
4. Commit + push  — git commit + git push
5. Node ops       — VPS adımları varsa her adımı ayrı ver, çıktı bekle
6. Task kapatma   — kullanıcı "task tamam" der
7. İşaretle       — status güncelle: [x] TAMAMLANDI · commit: XXXXXXXX · tarih: YYYY-MM-DD
8. Sonraki task
```

---

## Durum Göstergesi

```
[ ] BEKLEMEDE
[>] DEVAMEDİYOR
[x] TAMAMLANDI · commit: XXXXXXXX · tarih: YYYY-MM-DD
```

---

## Kritik Sprint — P1–P5

---

### TASK-01 · P2 · 🔴 D3: auction.status default="active"

**Plan:** Faz 2.2  
**Sorun:** `auctions.status default="completed"` → yeni açık artırma tamamlanmış görünüyor.

**Etkilenen dosyalar:**
- `backend/app/models/auction.py` — Model katmanı
- `backend/alembic/versions/` — Yeni migration

**Uygulama:**
1. `auction.py` modeli: `default="completed"` → `default="active"`
2. Alembic migration:
   ```python
   op.execute("ALTER TABLE auctions ALTER COLUMN status SET DEFAULT 'active'")
   op.execute("UPDATE auctions SET status = 'active' WHERE status = 'completed' AND winner_id IS NULL AND ended_at IS NULL")
   ```
   > Her satır ayrı `op.execute()` — asyncpg multi-statement kabul etmez.

**Test:**
- Yeni açık artırma oluştur → `status = "active"` olduğunu kontrol et
- Mevcut açık artırmaların status'u değişmedi

**Node ops:** Yok (deploy = git pull + alembic upgrade head + restart)

**Status:** [ ] BEKLEMEDE

---

### TASK-02 · P5 · 🔴 FK Düzeltmesi: gift_events + bids + direct_sales → SET NULL

**Plan:** Faz 2.3  
**Sorun:**
- `gift_events.stream_id ondelete="CASCADE"` — live_stream silinince finansal hediye kaydı siliniyor
- `bids.stream_id` — ondelete tanımsız → FK violation riski
- `direct_sales.stream_id ondelete="CASCADE"` — **YENİ BULGU** live_stream silinince tüm direct_sales + direct_sale_orders (CASCADE zinciri) siliniyor

**Etkilenen dosyalar:**
- `backend/app/models/gift_event.py` — CASCADE → SET NULL
- `backend/app/models/bid.py` — ondelete="SET NULL" ekle
- `backend/app/models/direct_sale.py` — CASCADE → SET NULL
- `backend/alembic/versions/` — Yeni migration

**Uygulama:**
1. `gift_event.py`: `ondelete="CASCADE"` → `ondelete="SET NULL"`
2. `bid.py`: `stream_id` FK'ya `ondelete="SET NULL"` ekle
3. `direct_sale.py`: `ondelete="CASCADE"` → `ondelete="SET NULL"`
4. `auction.py`: `stream_id` FK'ya `ondelete="SET NULL"` ekle — **yeni bulgu:** tanımsız bırakılmış, GC5 live_stream silince FK violation fırlatır
5. Alembic migration (her satır ayrı `op.execute()`):
   ```python
   op.execute("""
       ALTER TABLE gift_events
       DROP CONSTRAINT gift_events_stream_id_fkey,
       ADD CONSTRAINT gift_events_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   op.execute("""
       ALTER TABLE bids
       DROP CONSTRAINT IF EXISTS bids_stream_id_fkey,
       ADD CONSTRAINT bids_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   op.execute("""
       ALTER TABLE direct_sales
       DROP CONSTRAINT direct_sales_stream_id_fkey,
       ADD CONSTRAINT direct_sales_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   op.execute("""
       ALTER TABLE auctions
       DROP CONSTRAINT IF EXISTS auctions_stream_id_fkey,
       ADD CONSTRAINT auctions_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   ```

**Test:**
- Test live_stream sil → gift_events/bids/direct_sales/auctions stream_id NULL oldu, kayıtlar korundu
- direct_sale_orders da korundu (direct_sales var olmaya devam ettiği için)

**Node ops:** Yok

**Status:** [ ] BEKLEMEDE

---

### TASK-03 · P3 · 🔴 GC1: live_stream_viewers cleanup görevi

**Plan:** Faz 1.4 · R1=10 yıl  
**Bağımlılık:** TASK-02 tamamlanmış olmalı.

> ⚠️ **KIRILMA UYARISI (Impact Analizi):** `live_stream_viewers` tablosunda hem `joined_at` hem `left_at` kolonu var. `left_at IS NULL` = aktif izleyici. Sorgu `left_at IS NOT NULL` filtresi olmadan çalıştırılırsa aktif yayın izleyicileri silinebilir.

**Etkilenen dosyalar:**
- `backend/app/repositories/` veya `backend/app/services/` — Repository method
- `backend/app/worker.py` — Yeni cron görev

**Uygulama:**
1. Repository'ye (veya doğrudan worker use-case'e) sorgu ekle:
   ```python
   # R1 = 10 yıl = 3650 gün
   # left_at IS NOT NULL filtresi şart — aktif izleyicileri silmemek için
   DELETE FROM live_stream_viewers
   WHERE left_at IS NOT NULL
     AND joined_at < NOW() - INTERVAL '3650 days'
   ```
2. `worker.py`'de yeni cron görevi:
   ```python
   # worker.py'deki pattern: AsyncSessionLocal (get_db() context manager değil)
   async def cleanup_old_stream_viewers_task(ctx):
       async with AsyncSessionLocal() as db:
           result = await db.execute(
               text("DELETE FROM live_stream_viewers WHERE left_at IS NOT NULL AND joined_at < NOW() - INTERVAL '3650 days'")
           )
           await db.commit()
           logger.info(f"Deleted {result.rowcount} old stream viewer records")

   # Cron: Haftalık Çarşamba 04:00
   cron(cleanup_old_stream_viewers_task, weekday=3, hour=4, minute=0)
   ```

**Clean Architecture notu:** Görev iş mantığı basitse doğrudan worker.py içinde query kabul edilebilir. Karmaşıklaşırsa ayrı use case fonksiyonu.

**Test:**
- `worker.py` syntax hatası yok
- Test verisi ekleyip görevi manuel tetikle: `await cleanup_old_stream_viewers_task(ctx)`

**Node ops:** Yok (restart yeterli)

**Status:** [ ] BEKLEMEDE

---

### TASK-04 · P4 · 🔴 Float → Numeric(12,2) finansal kolonlar

**Plan:** Faz 2.1  
**Karar:** Endüstri standardı `Numeric(12,2)` — DB'de tam ondalıklı sakla, her katmanda `1.500,50 ₺` formatında sun.  
`exchange_rates.usd_try/eur_try` kur değerleri zaten `Numeric(10,4)` kalır.

**Etkilenen dosyalar:**
- `backend/app/models/` — listing, auction, bid, purchase, listing_offer, search_alert, user (price/amount alanları)
- `backend/app/models/market_index.py` — usd_try, eur_try (Numeric(10,4) kalır)
- `backend/app/schemas/` — Pydantic schema'lar: `float` → `Decimal`
- `backend/alembic/versions/` — Yeni migration
- `mobile/lib/models/` — Flutter model parse'ları: `toDouble()` → `toDouble()` (Decimal→float, aynı kalır ama `as num?` cast güvenli)
- `mobile/lib/utils/number_formatter.dart` — fiyat display formatı güncelle
- `mobile/lib/widgets/direct_sale_panel.dart` — fiyat tipleri, input ayarları
- `mobile/lib/widgets/auction_panel.dart` — cast güncellemesi

---

**1. Model güncellemeleri:**
```python
# ÖNCE: Float
from sqlalchemy import Float
price: Mapped[float] = mapped_column(Float)

# SONRA: Numeric(12,2) — max 9.999.999.999,99 ₺
from sqlalchemy import Numeric
from decimal import Decimal
price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
```

**2. Alembic migration — her ALTER ayrı `op.execute()`:**
```python
op.execute("ALTER TABLE listings ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
op.execute("ALTER TABLE listings ALTER COLUMN buy_it_now_price TYPE NUMERIC(12,2) USING buy_it_now_price::NUMERIC(12,2)")
op.execute("ALTER TABLE listings ALTER COLUMN last_sold_price TYPE NUMERIC(12,2) USING last_sold_price::NUMERIC(12,2)")
op.execute("ALTER TABLE listings ALTER COLUMN last_start_price TYPE NUMERIC(12,2) USING last_start_price::NUMERIC(12,2)")
op.execute("ALTER TABLE auctions ALTER COLUMN start_price TYPE NUMERIC(12,2) USING start_price::NUMERIC(12,2)")
op.execute("ALTER TABLE auctions ALTER COLUMN buy_it_now_price TYPE NUMERIC(12,2) USING buy_it_now_price::NUMERIC(12,2)")
op.execute("ALTER TABLE auctions ALTER COLUMN final_price TYPE NUMERIC(12,2) USING final_price::NUMERIC(12,2)")
op.execute("ALTER TABLE bids ALTER COLUMN amount TYPE NUMERIC(12,2) USING amount::NUMERIC(12,2)")
op.execute("ALTER TABLE purchases ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
op.execute("ALTER TABLE listing_offers ALTER COLUMN amount TYPE NUMERIC(12,2) USING amount::NUMERIC(12,2)")
op.execute("ALTER TABLE search_alerts ALTER COLUMN max_price TYPE NUMERIC(12,2) USING max_price::NUMERIC(12,2)")
op.execute("ALTER TABLE users ALTER COLUMN max_budget TYPE NUMERIC(12,2) USING max_budget::NUMERIC(12,2)")
op.execute("ALTER TABLE exchange_rates ALTER COLUMN usd_try TYPE NUMERIC(10,4) USING usd_try::NUMERIC(10,4)")
op.execute("ALTER TABLE exchange_rates ALTER COLUMN eur_try TYPE NUMERIC(10,4) USING eur_try::NUMERIC(10,4)")
```

**3. Pydantic schema'lar:** `float` → `Decimal`

**4. Serialization — FastAPI Decimal→float:**
FastAPI 0.115 `jsonable_encoder` Decimal'i `str`'e çevirir. Çözüm: tüm Pydantic schema base class'ına global encoder ekle:
```python
# backend/app/schemas/base.py (yeni veya mevcut base schema):
from decimal import Decimal
from pydantic import BaseModel, ConfigDict

class BaseSchema(BaseModel):
    model_config = ConfigDict(json_encoders={Decimal: float})
```
Tüm response schema'lar bu `BaseSchema`'dan türetilirse Decimal otomatik float serialize edilir.  
`response_model` kullanılmayan raw dict dönen endpoint'lerde (listing_utils.py:95,107,113 vb.) ek olarak `float(value)` wrap korunabilir.

**5. `to_price()` yardımcı fonksiyonu — `backend/app/utils/price.py` (yeni dosya):**
```python
# backend/app/utils/price.py
from decimal import Decimal, ROUND_HALF_UP

def to_price(value) -> Decimal:
    return Decimal(str(value)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
```
Tüm finansal hesaplamalar bu fonksiyondan geçer:
```python
from app.utils.price import to_price

total = to_price(quantity * unit_price)   # 3 × 33.33 → 99.99
```
`direct_sale_commands.py` içindeki `float(sale.price)` çağrıları → `sale.price` ya da `to_price(sale.price)`.

**6. FastAPI Decimal serileştirme — Pydantic v2 notu:**
`ConfigDict(json_encoders={Decimal: float})` Pydantic v2'de çalışır ama soft-deprecated. Kararlı alternatif:
```python
from pydantic import field_serializer

class AuctionOut(BaseSchema):
    start_price: Decimal

    @field_serializer('start_price', 'buy_it_now_price', 'final_price')
    def serialize_price(self, v: Decimal | None) -> float | None:
        return float(v) if v is not None else None
```
`BaseSchema` + `json_encoders` yaklaşımı kısa vadede yeterli; uzun vadede `field_serializer` yöntemi her schema'ya uygulanmalı.

**7. `bump_schema_version()`** — TASK-11 migration'ına ekle; TASK-11'de unutulmamalı.

---

**Flutter güncellemeleri:**

**TeqNumberFormatter — display her zaman 2 hane kuruş:**
```dart
// number_formatter.dart satır 67-68 — ÖNCE (değişken ondalık):
final isDecimal = numVal is double && numVal.remainder(1) != 0;
final pattern = isDecimal ? '#,##0.##' : '#,##0';

// SONRA — fiyat alanları her zaman 2 hane göster:
// format() metoduna `forceDecimals` parametresi ekle:
static String format(dynamic value, {
  String? fieldKey,
  String? locale,
  String? unit,
  bool forceDecimals = false,   // ← yeni parametre
}) {
  ...
  final pattern = (forceDecimals || (numVal is double && numVal.remainder(1) != 0))
      ? '#,##0.00'   // fiyat: her zaman 2 hane
      : '#,##0';
  ...
}
```
Tüm fiyat çağrıları `forceDecimals: true` alır:
```dart
TeqNumberFormatter.format(price, fieldKey: 'price', unit: '₺', forceDecimals: true)
// Sonuç: 100.00 → "100,00 ₺" | 1500.50 → "1.500,50 ₺"
```

**TeqNumericInputFormatter — fiyat alanlarında kuruş girişi:**
```dart
// direct_sale_panel.dart:1505, create_listing_screen içindeki fiyat input'ları:
// ÖNCE: TeqNumericInputFormatter(fieldKey: 'price')          // allowDecimal: false
// SONRA: TeqNumericInputFormatter(fieldKey: 'price', allowDecimal: true)  // kuruş girilebilir
```

**Flutter model parse — `double` olarak oku (Decimal→JSON float→Dart double):**
```dart
// auction.dart, direct_sale.dart, listing_offer.dart — değişiklik yok, toDouble() zaten doğru
// Backend Decimal → JSON float(e.g. 1500.50) → Dart (j['price'] as num?)?.toDouble() ✅
// auction_panel.dart:143-145 cast güncelle:
// ÖNCE: result['price'] as double?
// SONRA: (result['price'] as num?)?.toDouble()   // num? → güvenli cast
```

**direct_sale_panel.dart hesaplama:**
```dart
// Satır 1090:
// ÖNCE: final total = _qty * widget.state.price;  (double * double → double, ondalık kayabilir)
// SONRA: double total = double.parse((_qty * widget.state.price).toStringAsFixed(2));
```

---

**Kapsamlı denetim bulguları (agent, 2026-09-21):**

> Aşağıdaki tüm dosya:satır'lar yukarıdaki uygulama adımlarına karşılık gelir.

**🔴 KRİTİK — DB modelleri Float (5 model)**

| Model dosyası | Sütun | Fix |
|---|---|---|
| `backend/app/models/auction.py:16` | `start_price: Mapped[float] = mapped_column(Float)` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/auction.py:17` | `buy_it_now_price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/auction.py:18` | `final_price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/bid.py:19` | `amount: Mapped[float] = mapped_column(Float)` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/listing.py:29` | `price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/listing.py:44` | `buy_it_now_price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/listing.py:45` | `last_sold_price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/listing.py:46` | `last_start_price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/listing_offer.py:23` | `amount Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/purchase.py:16` | `price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/user.py:40` | `max_budget Float` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/search_alert.py:22` | `max_price Float` | `Numeric(12,2)`, `Mapped[Decimal]` |

**🟡 DB modeli Numeric(10,2) → (12,2)**

| Model dosyası | Sütun | Fix |
|---|---|---|
| `backend/app/models/direct_sale.py:18` | `price Numeric(10,2)` | `Numeric(12,2)`, `Mapped[Decimal]` |
| `backend/app/models/direct_sale.py:46` | `unit_price Numeric(10,2)` | `Numeric(12,2)`, `Mapped[Decimal]` |

**🟡 Pydantic schema — `float` → `Decimal` (BaseSchema yöntemi)**

| Dosya | Satırlar |
|---|---|
| `backend/app/schemas/auction.py` | 8, 9, 43, 55, 66-68 — tüm fiyat alanları `float` |
| `backend/app/schemas/direct_sale.py` | 9, 66, 86, 93-94, 99, 111-112 |
| `backend/app/schemas/listing.py` | 8, 21 — `amount: float` |

**🟡 Backend `float()` sarmalayıcılar — kaldırılacak**

| Dosya | Satırlar | Fix |
|---|---|---|
| `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` | 104, 121, 135, 151, 232, 239, 258, 317, 408 | `float(x)` → `x` (Decimal doğrudan) |
| `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` | 239 | `total_sold * float(sale.price)` → `(Decimal(str(sale.price)) * total_sold).quantize(Decimal("0.01"))` |
| `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` | 337 | `price=0.0` → `price=Decimal('0.00')` |
| `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` | 348 | `unit_price: float` → `unit_price: Decimal` |
| `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` | 632-633, 667-668 | `float(agg.unit_price)`, `float(agg.total_price)` → raw Decimal |
| `backend/app/use_cases/direct_sales/direct_sale_scheduler.py` | 74, 97, 113 | `float(sale.price)` → `sale.price`; total_revenue → `quantize(Decimal("0.01"))` |
| `backend/app/use_cases/direct_sales/direct_sale_redis.py` | 164 | `"price": float(data["price"])` → `"price": str(data["price"])` (Redis'e string) |
| `backend/app/routers/auth.py` | 720, 729, 735 | `float(r.final_price)` vb. → Decimal doğrudan ya da `to_price()` |
| `backend/app/routers/auth.py` | 797 | `func.sum(unit_price * quantity)` DB'de hesaplanıyor — OK |
| `backend/app/use_cases/auctions/commands/auction_commands.py` | 104-106, 157, 169, 243 | Redis oku/yaz — Decimal uyumlu yapılacak |
| `backend/app/use_cases/auctions/queries/auction_queries.py` | 55, 57, 61 | `float()` → Decimal |
| `backend/app/use_cases/streams/queries/get_commerce_activity.py` | 33, 55 | `float(bid.amount)`, `float(order.unit_price)` → raw Decimal |

**🟡 ClickHouse — `Decimal(10,2)` → `Decimal(12,2)`**

| Dosya | Satır |
|---|---|
| `backend/app/database_clickhouse.py` | 159: `unit_price Nullable(Decimal(10,2))` → `Decimal(12,2)` |
| `backend/app/database_clickhouse.py` | 160: `total_price Nullable(Decimal(10,2))` → `Decimal(12,2)` |
| `backend/app/database_clickhouse.py` | 517-518 | ClickHouse'dan okurken `float()` cast → Decimal |

**🔴 Flutter — `.toInt()` fiyat kesme (critical)**

| Dosya | Satır | Sorun | Fix |
|---|---|---|---|
| `mobile/lib/screens/listing_detail_screen.dart` | 1833 | `(item['price'] as num).toInt()` → `99.99 → 99` | `TeqNumberFormatter.format(item['price'], fieldKey: 'price', unit: '₺', forceDecimals: true)` |
| `mobile/lib/screens/live/seller_report_screen.dart` | 45-54 | `_fmtPrice` → `val.toInt().toString()` | `TeqNumberFormatter.format(val, forceDecimals: true)` ile değiştir |

**🟡 Flutter — `allowDecimal: false` olan fiyat input'ları**

| Dosya | Satır | Fix |
|---|---|---|
| `mobile/lib/screens/create_listing_screen.dart` | 1230 | `TeqNumericInputFormatter(fieldKey: 'price')` → `allowDecimal: true` ekle |
| `mobile/lib/widgets/direct_sale_panel.dart` | 1505, 1531 | aynı |
| `mobile/lib/screens/edit_listing_screen.dart` | 735 | aynı |
| `mobile/lib/screens/listing_detail_screen.dart` | 1678 | aynı |

**🟡 Flutter — `#,##0` (decimal göstermiyor)**

| Dosya | Satır | Fix |
|---|---|---|
| `mobile/lib/utils/number_formatter.dart` | 67-68 | `forceDecimals: true` ile `#,##0.00` pattern'i aktif et (yukarıdaki koda eklendi) |
| `mobile/lib/screens/pro_insights_screen.dart` | 391, 659, 741, 748 | `NumberFormat('#,##0', 'tr_TR')` → `TeqNumberFormatter.format(v, forceDecimals: true)` |
| `mobile/lib/screens/live/swipe_live_screen.dart` | 1969-1973, 2104 | `#,##0` pattern → `forceDecimals: true` |

> **Not:** `market_index.py` `usd_try/eur_try` (kur), `analytics.py` `duration_seconds`, ClickHouse `user_events.price_point` Float64 (analitik) — bunlar para birimi değil, olduğu gibi kalır.

---

**Test:**
- Staging'de `alembic upgrade head` → `SELECT price FROM listings` → `1500.50` formatı
- `GET /api/listings` → `"price": 1500.50` (number, string değil)
- Ilan oluştur: `1.500,50` gir → DB'de `1500.50` ✅
- Direct sale: 3 adet × 33,33 → toplam `100,00 ₺` (yuvarlama doğru)
- Tüm fiyat ekranlarında `#.###,00` format görünüyor

**Node ops:** Staging önce, sonra prod.

**Status:** [ ] BEKLEMEDE

---

### TASK-05 · P1 · 🔴 PgBouncer Aktivasyonu

**Plan:** Faz 3.1  
**Sorun:** 4 uvicorn + 2 ARQ = max 120 bağlantı talebi; PostgreSQL max_connections=100.

**Etkilenen dosyalar:**
- `deploy/scale/V1.4/node5/pgbouncer/pgbouncer.ini` — Yeni dosya
- `deploy/scale/V1.4/node5/pgbouncer/userlist.txt` — Yeni dosya (şifre hash)
- `deploy/scale/V1.4/node5/systemd/pgbouncer.service` — Yeni systemd birimi
- `deploy/scale/V1.4/node5/systemd/teqlif.service` — PgBouncer bağımlılığı ekle
- `backend/app/config.py` — `use_pgbouncer = True`
- node5 `/etc/postgresql/postgresql.conf` — `port = 5433` (PgBouncer 5432 alır)

**Uygulama:**

1. `pgbouncer.ini`:
   ```ini
   [databases]
   teqlif = host=127.0.0.1 port=5433 dbname=teqlif
   
   [pgbouncer]
   listen_addr = 127.0.0.1
   listen_port = 5432
   auth_type = md5
   auth_file = /etc/pgbouncer/userlist.txt
   pool_mode = transaction
   max_client_conn = 200
   default_pool_size = 30
   reserve_pool_size = 5
   server_reset_query = DISCARD ALL
   log_connections = 0
   log_disconnections = 0
   ```

2. `config.py`: `use_pgbouncer: bool = True`

3. `teqlif.service`'e `Requires=pgbouncer.service` + `After=pgbouncer.service` ekle

4. `.env.production` DB_PORT değişiklik gerektirmez (PgBouncer 5432'yi karşılar, PostgreSQL 5433'e geçer)

5. **Zorunlu asyncpg `statement_cache_size=0`:** PgBouncer transaction mode ile asyncpg prepared statement cache uyumsuz — `InvalidSQLStatementNameError` hatası alınır. `backend/app/database.py`'de engine oluşturulurken eklenmeli:
   ```python
   # PgBouncer transaction mode: prepared statement cache devre dışı bırakılmalı
   engine = create_async_engine(
       DATABASE_URL,
       poolclass=NullPool,
       connect_args={"statement_cache_size": 0},  # ← ZORUNLU
   )
   ```

**Test:**
- **Staging önce** — `pg_stat_activity` ile bağlantı sayısı max 30
- `SELECT count(*) FROM pg_stat_activity WHERE datname='teqlif'` — 30'un altında
- `EXPLAIN` gibi hazırlıklı sorgu içeren endpoint'ler hata vermiyor (`InvalidSQLStatementNameError` yok)
- Transaction pool mode ile `SET search_path` çalışmıyor olabilir; test et

**Node ops (staging → prod sırası):**
1. node3'te pgbouncer.ini yerleştir
2. `sudo systemctl enable pgbouncer && sudo systemctl start pgbouncer`
3. PostgreSQL port'unu 5433'e al: `postgresql.conf` → `port=5433` → restart
4. `sudo teqlif-restart` → log izle
5. `SELECT count(*) FROM pg_stat_activity` çalıştır

**Status:** [ ] BEKLEMEDE

---

## Yüksek Öncelik Sprint — P6–P12

---

### TASK-06 · P6 · 🟡 ClickHouse TTL → 365 gün

**Plan:** Faz 4.1 · R9=■1 yıl  
**Bağımlılık:** Yok (non-blocking ALTER, production'da çalıştırılabilir)

**Uygulama (node5 ClickHouse — VPS komutu):**
```sql
ALTER TABLE user_events MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE feed_analytics MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE search_events MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE swipe_live_events MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE direct_sale_events MODIFY TTL created_at + INTERVAL 365 DAY;
```

**Backend kod değişikliği:** Yok — `database_clickhouse.py`'da TTL tanımları create-table sırasında kullanılır; mevcut tabloları doğrudan ALTER ile değiştir.

**Test:**
```sql
SELECT table, ttl_expression
FROM system.tables
WHERE database = 'teqlif_prod_analytics';
```
Her tabloda `365 DAY` görünmeli.

**Node ops:**
1. `clickhouse-client --database teqlif_prod_analytics` ile bağlan
2. Her ALTER TABLE komutunu sırayla çalıştır, çıktısını paylaş
3. `system.tables` sorgusu ile doğrula

**Status:** [ ] BEKLEMEDE

---

### TASK-07 · P7 · 🟡 R9b: user_interactions retention 90→365 gün

**Plan:** Faz 1.2 R9b=■1 yıl  
**Dosya:** `backend/app/worker.py`

**Uygulama:**
```python
# ÖNCE (worker.py içindeki cleanup_old_user_interactions_task):
# DELETE FROM user_interactions WHERE created_at < NOW() - INTERVAL '90 days'

# SONRA:
# DELETE FROM user_interactions WHERE created_at < NOW() - INTERVAL '365 days'
```

Görevin içindeki INTERVAL değerini 90 → 365 gün olarak güncelle.

**Test:**
- `user_interactions`'da 90-365 gün arası veri varsa silinmediğini kontrol et (SELECT COUNT)

**Node ops:** Yok (restart yeterli)

**Status:** [ ] BEKLEMEDE

---

### TASK-08 · P8 · 🟡 MinIO Lifecycle Policy (node1 + node4)

**Plan:** Faz 1.5

**Uygulama (VPS komutları — node1'de, sonra node4'te):**
```bash
# listings/ — 365 gün
mc ilm add --expiry-days 365 teqlif/teqlif/listings/

# stories/ — 2 gün
mc ilm add --expiry-days 2 teqlif/teqlif/stories/

# dm/ — 14 gün
mc ilm add --expiry-days 14 teqlif/teqlif-dm/
```

**Doğrulama:**
```bash
mc ilm ls teqlif/teqlif/listings/
mc ilm ls teqlif/teqlif/stories/
mc ilm ls teqlif/teqlif-dm/
```

**Node ops:**
1. node1'de mc alias kontrol: `mc alias ls`
2. Lifecycle rule'ları ekle (yukarıdaki komutlar)
3. node4'te tekrarla

**Status:** [ ] BEKLEMEDE

---

### TASK-09 · P9 · 🟡 W1/W3/W4/W5 ARQ Frekans Değişikliği

**Plan:** Faz 6.1 · W1=■ W3=■ W4=■ W5=■  
**Dosya:** `backend/app/worker.py`

> ⚠️ **3 Kritik Bug Bu Task'ta Düzeltilmeli (Impact Analizi):**
> 1. **W4 Redis key mismatch** — `populate_foryou_feed_task` `feed:{uid}:foryou` (LIST) yazıyor, API `feed:foryou:{uid}` (String) okuyor → W4 çıktısı hiçbir yerde tüketilmiyor.
> 2. **W3 TTL uyumsuzluğu** — `condition_pref:{uid}` TTL=1500s (25dk), 4x/gün = 6h aralık → 5.5 saatin condition scoring'i eksik.
> 3. **W5 TTL uyumsuzluğu** — `trending:listings:velocity` TTL=1800s (30dk), 4x/gün = 6h aralık → trending 5.5 saat boş kalır.

**Mevcut → Hedef:**
| Görev | Mevcut | Hedef |
|-------|--------|-------|
| `compute_user_interests_task` | Her 15 dk | 4x/gün: 00:00, 06:00, 12:00, 18:00 |
| `compute_user_condition_preferences_task` | Her 15 dk | 4x/gün: 00:10, 06:10, 12:10, 18:10 |
| `populate_foryou_feed_task` | Saatlik :00 | 4x/gün: 00:20, 06:20, 12:20, 18:20 |
| `compute_trending_listings_task` | Her 30 dk | 4x/gün: 00:30, 06:30, 12:30, 18:30 |

**Uygulama:** ARQ `cron()` tanımlarını güncelle + 3 bug düzelt:
```python
# ÖNCE
cron(compute_user_interests_task, minute={0, 15, 30, 45})

# SONRA — frekans değişikliği
cron(compute_user_interests_task, hour={0, 6, 12, 18}, minute=0)
cron(compute_user_condition_preferences_task, hour={0, 6, 12, 18}, minute=10)
cron(populate_foryou_feed_task, hour={0, 6, 12, 18}, minute=20)
cron(compute_trending_listings_task, hour={0, 6, 12, 18}, minute=30)
```

**W4 key mismatch düzeltmesi** (`foryou_worker.py` + `worker.py`):
```python
# 1. foryou_worker.py — populate_foryou_feed_task içinde:
# ÖNCE (hatalı): await redis.rpush(f"feed:{uid}:foryou", ...)  # foryou_worker.py:85
#                await redis.expire(f"feed:{uid}:foryou", _FORYOU_TTL)
# SONRA (doğru): await redis.set(f"feed:foryou:{uid}", json.dumps(feed_ids), ex=_FORYOU_TTL)
# Not: FeedQueries.get_foryou_feed() redis.get(f"feed:foryou:{user_id}") okuyor (feed_queries.py:633)

# 2. worker.py:994 — compute_user_interests_task invalidasyon satırı da güncellenmeli:
# ÖNCE (eski hatalı key): invalidation_keys.append(f"feed:{uid}:foryou")
# SONRA (doğru key):     invalidation_keys.append(f"feed:foryou:{uid}")
```

**W3 TTL düzeltmesi** (`worker.py`'de `compute_user_condition_preferences_task`):
```python
# ÖNCE: await redis.set(f"condition_pref:{uid}", ..., ex=1500)  # 25 dk
# SONRA: await redis.set(f"condition_pref:{uid}", ..., ex=21600)  # 6 saat
```

**W5 TTL düzeltmesi** (`worker.py`'de `compute_trending_listings_task`):
```python
# ÖNCE: await redis.set("trending:listings:velocity", ..., ex=1800)  # 30 dk
# SONRA: await redis.set("trending:listings:velocity", ..., ex=21600)  # 6 saat
```

**Test:**
- Bir sonraki 00:00'da: 4 görevin de çalıştığı log görünüyor
- 6 saatte toplam 4 çalışma
- `redis-cli GET feed:foryou:1` → değer var (W4 key mismatch düzeltildi)
- `redis-cli TTL condition_pref:1` → ~21600 s
- `redis-cli TTL trending:listings:velocity` → ~21600 s

**Node ops:** `sudo teqlif-restart`

**Status:** [ ] BEKLEMEDE

---

### TASK-10 · P9b · 🟡 W2/W6/W7 ARQ Frekans Değişikliği

**Plan:** Faz 6.1 · W2=■ W6=■ W7=■  
**Dosya:** `backend/app/worker.py`

> ⚠️ **ALS/BPR TTL Kritik Uyumsuzluğu (Impact Analizi):** W6/W7 haftalık eğitime geçince ALS/BPR vektörlerinin TTL'i de uzatılmalı. Mevcut TTL=90000s (25 saat) — haftalık eğitimde 6 gün boyunca ALS cache'i boş kalır, feed kişiselleştirmesinin ~%20'si kaybolur. `bpr:rec:{uid}` için 7 gün TTL ayarlanmalı.

**Mevcut → Hedef:**
| Görev | Mevcut | Hedef |
|-------|--------|-------|
| `backfill_listing_embeddings_task` | Her 30 dk | Gece: 02:00, 03:00 |
| `train_feed_als_task` | Günlük 01:30 | Haftalık Paz 01:30 |
| `train_swipe_live_als_task` | Günlük 01:00 | Haftalık Paz 01:00 |

```python
# ÖNCE
cron(backfill_listing_embeddings_task, minute={0, 30})
cron(train_feed_als_task, hour=1, minute=30)
cron(train_swipe_live_als_task, hour=1, minute=0)

# SONRA
cron(backfill_listing_embeddings_task, hour={2, 3}, minute=0)
cron(train_feed_als_task, weekday=6, hour=1, minute=30)    # Paz
cron(train_swipe_live_als_task, weekday=6, hour=1, minute=0)   # Paz
```

**ALS/BPR TTL uzatması** (`bpr_service.py` veya worker içinde cache yazan yer):
```python
# NOT: bpr_service.py:40 _REDIS_TTL = 7 * 86400 = 604800 ZATEN DOĞRU — değişiklik yok
# Doğrulama: bpr_service.py satır 40: `_REDIS_TTL = 7 * 86400  # = 604800 saniye = 7 gün`
# ÖNCE (gerçek): _REDIS_TTL = 604800  # 7 gün (mevcut kod zaten doğru)
# SONRA: değişiklik gerekmez — TTL zaten haftalık eğitimle uyumlu
# seller:badge, trust_score, influence_rank gibi diğer ML key'leri haftalık eğitim varsa 7 güne çıkar (gerekiyorsa)
```

**Test:**
- Gündüz `backfill_listing_embeddings_task` çalışmıyor (log kontrol)
- 02:00 ve 03:00'de çalışıyor
- Pazar sabahı train sonrası `redis-cli TTL bpr:rec:1` → ~604800 s

**Node ops:** `sudo teqlif-restart`

**Status:** [ ] BEKLEMEDE

---

### TASK-11 · P10 · 🟡 Composite Index'ler

**Plan:** Faz 3.2  
**Not:** `CREATE INDEX CONCURRENTLY` yasak (teqlif env.py transaction kullanır).

**Etkilenen dosyalar:**
- `backend/alembic/versions/` — Yeni migration
- Model `__table_args__` güncellemesi (yeni index tanımları)

**Mevcut duruma göre gerçek eksik listesi:**
```
✅ analytics_events (user_id, created_at)    — ix_analytics_events_user_created MEVCUT, ekleme
✅ bids (stream_id, created_at)              — ix_bids_stream_created MEVCUT, ekleme
✅ follows (follower_id, followed_id)        — UniqueConstraint implicit index MEVCUT, ekleme

⚠️ tuci_transactions (user_id, created_at)  — EKSIK (sadece user_id tek-kolon var)
⚠️ purchases (buyer_id, created_at)         — EKSIK
⚠️ user_interactions (user_id, created_at) — EKSIK (user_id+item_id var ama ML queries için created_at composite yok)
⚠️ listings (user_id, status)               — EKSIK (satıcının aktif ilanları için)
⚠️ listing_offers (listing_id, status)      — EKSIK (D7 sonrası, status alanı eklendikten sonra)
```

**Uygulama:**
```python
# Alembic migration — her index ayrı op.execute()
op.execute("CREATE INDEX ix_tuci_transactions_user_created ON tuci_transactions (user_id, created_at DESC)")
op.execute("CREATE INDEX ix_purchases_buyer_created ON purchases (buyer_id, created_at DESC)")
op.execute("CREATE INDEX ix_user_interactions_user_created ON user_interactions (user_id, created_at)")
op.execute("CREATE INDEX ix_listings_user_status ON listings (user_id, status)")
# listing_offers index: TASK-yeni-A tamamlandıktan SONRA ayrı migration ile:
# op.execute("CREATE INDEX ix_listing_offers_listing_status ON listing_offers (listing_id, status)")
```

Model dosyalarına da `Index(...)` tanımı eklenmeli:
- `tuci_transaction.py` → `__table_args__` ekle
- `purchase.py` → `__table_args__` ekle
- `analytics.py` → `ix_user_interactions_user_created` ekle
- `listing.py` → `ix_listings_user_status` ekle

> **TASK-23 bağımlılık notu:** TASK-23 (`tuci→teqlik` rename) tamamlanınca `tuci_transactions` tablosu ve bu index adı değişecek. TASK-23 migration'ında `RENAME INDEX ix_tuci_transactions_user_created TO ix_teqlik_transactions_user_created` eklenmeli.

**Test:**
- `\d tuci_transactions` ile index listesi kontrol
- `EXPLAIN SELECT * FROM tuci_transactions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 20` → Index Scan görünmeli
- `EXPLAIN SELECT * FROM user_interactions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 120` → Index Scan

**Node ops:** Staging önce, prod sonra.

**Status:** [ ] BEKLEMEDE

---

### TASK-12 · P11/P12 · 🟢 GC3/GC4/GC5: listing_offers + exchange_rates + live_streams cleanup

**Plan:** Faz 1.4  
**Bağımlılık:**
- GC3: **TASK-yeni-A tamamlanmadan çalıştırma** — status alanı olmadan aktif teklifler de silinir (`feed.py:292` LEFT JOIN ile teklif sayısı gösteriliyor)
- GC5: **TASK-02 tamamlanmadan çalıştırma** — `auctions.stream_id` FK tanımsız; stream silinince FK violation fırlatır ve görev başarısız olur

**Dosya:** `backend/app/worker.py`

> **Import notu:** `get_db()` (`database.py:45`) bir async generator — context manager değil; `async with get_db() as db:` syntax'ı `AttributeError: __aenter__` fırlatır. Tüm worker task'ları `async with AsyncSessionLocal() as db:` kullanmalı (worker.py:210,255,278 pattern'i). `from app.database import AsyncSessionLocal` top-level import'a ekle.

**Uygulama — 3 yeni görev:**
```python
async def cleanup_old_listing_offers_task(ctx):
    # R6 = 1 yıl — TASK-yeni-A tamamlandıktan sonra çalıştır
    # status IN ('declined','expired') filtresi şart — aktif teklifler korunmalı
    # (feed.py:292 listing_offers LEFT JOIN ile teklif sayısı gösteriyor)
    async with AsyncSessionLocal() as db:
        result = await db.execute(text(
            "DELETE FROM listing_offers "
            "WHERE status IN ('declined', 'expired') "
            "AND created_at < NOW() - INTERVAL '365 days'"
        ))
        await db.commit()
        logger.info(f"[GC3] Deleted {result.rowcount} old listing offers")

async def cleanup_old_exchange_rates_task(ctx):
    # R10 = 10 yıl — TABLO ADI: exchange_rates (market_index değil!)
    async with AsyncSessionLocal() as db:
        result = await db.execute(text(
            "DELETE FROM exchange_rates WHERE date < CURRENT_DATE - INTERVAL '3650 days'"
        ))
        await db.commit()
        logger.info(f"[GC4] Deleted {result.rowcount} old exchange rate records")

async def cleanup_old_streams_task(ctx):
    # R3 = 10 yıl — biten live_streams
    # BAĞIMLILIK: TASK-02 (FK SET NULL) tamamlanmış olmalı
    async with AsyncSessionLocal() as db:
        result = await db.execute(text(
            "DELETE FROM live_streams WHERE status = 'ended' "
            "AND ended_at < NOW() - INTERVAL '3650 days'"
        ))
        await db.commit()
        logger.info(f"[GC5] Deleted {result.rowcount} old live streams")

# Cron:
cron(cleanup_old_listing_offers_task, weekday=5, hour=4, minute=0)    # Cuma 04:00
cron(cleanup_old_exchange_rates_task, day=1, hour=5, minute=0)        # Ayın 1'i 05:00
cron(cleanup_old_streams_task, day=1, hour=6, minute=0)               # Ayın 1'i 06:00
```

**Test:**
- Her görevi manuel tetikle, rowcount logunu kontrol et
- `SELECT MIN(date) FROM exchange_rates` → 10 yıldan eski kayıt yok

**Status:** [ ] BEKLEMEDE

---

## Orta Öncelik Sprint — P13–P15

---

### TASK-13 · P13 · 🟡 Keyset Pagination — Feed + Cüzdan

**Plan:** Faz 5.2  
**Etkilenen dosyalar:**
- `backend/app/routers/listings.py` — Router: yeni query param `cursor` (additive)
- `backend/app/routers/feed.py` — `GET /feed`, `GET /feed/for-you`
- `backend/app/routers/search.py` — search offset parametreleri
- `backend/app/use_cases/listing_use_cases.py` (veya benzeri) — Use Case: keyset sorgu
- `backend/app/repositories/listing_repository.py` — Repository: SQL değişikliği
- `mobile/lib/` — Feed ViewModel + Pagination logic (MVVM) + Hive cache format

> ⚠️ **Koordinasyon Zorunlu (Impact Analizi):**
> 1. **`page`/`offset` parametreleri kaldırılmamalı** — Flutter tüm sayfalama için offset-based kullanıyor (`home_view_model.dart:147,287`, `swipe_live_screen.dart:584`). `cursor` parametresi ADDITIVELY eklenmeli, eski parametreler deprecated period olmadan silinmemeli.
> 2. **Hive `homeCache` box güncellenmeli** — Mevcut format `raw JSON + page offset` saklıyor (`home_view_model.dart:77,156,179,256`). `cacheVersion` mekanizması **hiç mevcut değil** — sıfırdan implement edilmeli. Keyset'e geçince eski cache çakışacak, `cacheBox.clear()` ile temizlenmeli.
> 3. **`GET /api/feed/recent` zaten cursor-benzeri** — `since_id` + `max_id` parametreleri var (feed.py:105-106); bu endpoint için additive değil, zaten uyumlu.
> 4. **Logout Hive clear eksikliği (yeni bulgu):** `StorageService.clear()` (`auth_service.dart:253`) sadece secure storage ve SharedPreferences'ı temizliyor — `api_cache` ve `homeCache` Hive box'larını temizlemiyor. Farklı kullanıcı giriş yapınca önceki kullanıcının feed verisi görünebilir. Bu task kapsamında `logout()` akışına `Hive.box('homeCache').clear()` ve `Hive.box('api_cache').clear()` eklenmeli.

**Uygulama özeti:**

Backend:
```python
# Query: (created_at, id) tuple cursor
WHERE status = 'active'
  AND (created_at, id) < (:cursor_at, :cursor_id)
ORDER BY created_at DESC, id DESC
LIMIT 20
# Eski offset parametresini de koru (deprecated ama bozma)
```

Flutter (MVVM):
- ViewModel'de `_cursor` state tutulur
- `fetchMore()` metodu cursor'ı günceller
- View sadece `ref.watch(feedViewModel)` ile render eder
- Hive cache: `cacheVersion` artır → eski offset-based cache otomatik temizlenir

**Test:**
- 3 sayfalık veri yükle: offset'te "kayıp/tekrar" yok
- p95 < 200 ms
- Eski `?page=2` isteği hâlâ çalışıyor (backward compat)

**Status:** [ ] BEKLEMEDE

---

### TASK-14 · P14 · 🟡 Endpoint Cache Stratejisi

**Plan:** Faz 5.3  
**Etkilenen dosyalar:**
- `backend/app/routers/listings.py`, `users.py`, `catalog.py`, `app_config.py`
- `backend/app/cache.py` (veya mevcut fastapi-cache decorator'ları)

**ADR §9 cache taksonomisi uygulaması:**

| Endpoint | TTL | Kategori | Invalidasyon |
|---------|-----|---------|-------------|
| `GET /listings/{id}` | 60 sn | EPHEMERAL | Listing update |
| `GET /users/{id}` | 5 dk | EPHEMERAL | Profile update |
| `GET /catalog/categories` | 1 saat | SCHEMA_VERSIONED | bump_schema_version() |
| `GET /app-config` | 10 dk | SCHEMA_VERSIONED | bump_schema_version() |
| `GET /listings/feed` | 30 sn | ALGORITHMIC | TTL expire |

**Status:** [ ] BEKLEMEDE

---

### TASK-15 · P15 · 🟡 Feed N+1 Düzeltmesi

**Plan:** Faz 5.1  
**Etkilenen dosyalar:**
- `backend/app/use_cases/listings/queries/get_swipe_feed.py`
- `backend/app/use_cases/feed/queries/feed_queries.py`
- `backend/app/use_cases/listings/queries/search_listings_query.py`

> **Mevcut sorun:** Feed çekiminde her ilan için ayrı `db.get(User, listing.user_id)` — N ilan = N+1 sorgu.  
> `likes_count` Redis'ten batch alınıyor (doğru). Seller badge/trust/influence de Redis'ten batch — doğru.  
> **Düzeltme gereken:** User JOIN'i DB'de tek sorguda yapılmalı.

**Uygulama — Listing + User tek JOIN:**
```python
# listing_repository.py — paginated feed query
from sqlalchemy import select
from app.models.listing import Listing
from app.models.user import User

async def get_feed_page(
    db: AsyncSession,
    cursor_at: datetime | None,
    cursor_id: int | None,
    limit: int = 20,
) -> list[tuple[Listing, User]]:
    q = (
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(Listing.status == "active")
    )
    if cursor_at and cursor_id:
        q = q.where(
            (Listing.created_at < cursor_at) |
            ((Listing.created_at == cursor_at) & (Listing.id < cursor_id))
        )
    q = q.order_by(Listing.created_at.desc(), Listing.id.desc()).limit(limit)
    rows = await db.execute(q)
    return rows.all()
```
`(listing, user)` tuple'ları döner — `_card_dict(listing, user, ...)` çağrılarına doğrudan gider.

> **Not:** `fav_count` için DB correlated subquery ekleme — bu Redis'ten (`likes_count`) geliyor, DB'de O(n) subquery açma. Sadece User JOIN tek sorguda yeterli.

**Test:** `EXPLAIN ANALYZE` → listings + users için tek `Hash Join` / `Nested Loop`, ayrı kullanıcı sorgusu yok

**Bağımlılık:** TASK-yeni-N ile aynı dosyaları etkiler — aynı sprint'te uygulanmalı.

**Status:** [ ] BEKLEMEDE

---

## Kritik Sprint Ek Tasklar — P5c–P5f

> Sonradan tespit edilen kritik öncelikli tasklar. P1–P5 grubuyla aynı sprint'te uygulanmalı.

---

### TASK-yeni-E · P5g · 🔴 S1/S9: BigInteger PK + DM Normal Mesaj Retention

**Plan:** Faz 2.1 (Model katmanı — TASK-04 ile aynı sprint)  
**Kaynak:** `findings.md §S1, §S9`

**Sorun:**
1. `direct_messages.id` `int4` (max 2,147,483,647) — 100K kullanıcı × 5 msg/gün = 500K/gün → ~11.7 yılda taşar. `ALTER COLUMN ... BIGINT` production'da tam tablo kilidi — **sıfırdan başlarken şimdi değiştir, sonra imkânsız.**
2. `notifications.id` int4 — 30 günde siliniyor, bounded risk ama sıfırdan düzeltmek maliyetsiz.
3. `worker.py` DM cleanup'ı yalnızca `is_hidden=TRUE` olanları siliyor — **normal mesajlar hiç silinmiyor.** 100K kullanıcı × 5 msg/gün = tablo sonsuz büyür.

**Etkilenen dosyalar:**
- `backend/app/models/message.py` — `id: Mapped[int]` → `Mapped[int64]` (SQLAlchemy `BigInteger`)
- `backend/app/models/notification.py` — aynı
- `backend/alembic/versions/` — Yeni migration
- `backend/app/worker.py` — DM cleanup'a normal mesaj kuralı ekle

**1. Model güncellemesi:**
```python
# models/message.py
from sqlalchemy import BigInteger

class DirectMessage(Base):
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)

# models/notification.py — aynı değişiklik
```

**2. Alembic migration:**
```python
op.execute("ALTER TABLE direct_messages ALTER COLUMN id TYPE BIGINT")
op.execute("ALTER TABLE notifications ALTER COLUMN id TYPE BIGINT")
```

**3. DM normal mesaj retention (worker.py):**
```python
async def cleanup_old_direct_messages_task(ctx):
    async with AsyncSessionLocal() as db:
        # Her iki taraf da silmişse 365 gün sonra sil
        await db.execute(text(
            "DELETE FROM direct_messages "
            "WHERE is_deleted_by_sender = TRUE "
            "AND is_deleted_by_receiver = TRUE "
            "AND created_at < NOW() - INTERVAL '365 days'"
        ))
        # Hiç okunmamış ve 365+ gün eski mesajlar (inbox'ta terk edilmiş)
        await db.execute(text(
            "DELETE FROM direct_messages "
            "WHERE is_read = FALSE "
            "AND created_at < NOW() - INTERVAL '365 days'"
        ))
        await db.commit()

cron(cleanup_old_direct_messages_task, weekday=1, hour=3, minute=0)  # Pazartesi 03:00
```
> **Not:** `is_deleted_by_sender`/`is_deleted_by_receiver` kolon adlarını `message.py`'de doğrula — model farklı adlandırılmışsa uyarla.

**Test:**
- `SELECT data_type FROM information_schema.columns WHERE table_name='direct_messages' AND column_name='id'` → `bigint`
- Worker görevi çalıştır → normal mesajlar silinmiyor (365 günden kısa), eski silinmişler gidiyor

**Node ops:** `alembic upgrade head` — staging önce.

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-F · P5h · 🔴 S4: Kritik Endpoint'lere `response_model=` Ekle

**Plan:** Faz 2.1 (TASK-04 ile paralel — şema çalışması)  
**Kaynak:** `findings.md §S4`

**Sorun:** En sık çağrılan endpoint'lerde `response_model=` yok → Pydantic doğrulama çalışmıyor, internal field'lar client'a sızabilir (`hashed_password`, `is_shadowbanned`, `is_admin`, ML vektörleri).

**Tipsiz endpoint'ler (6 adet):**
```
GET  /listings               ← en sık çağrılan; feed payload buradan geliyor
GET  /listings/{id}          ← detay sayfası
GET  /auth/me                ← her açılışta çağrılıyor
GET  /auth/init              ← app init; ne döndüğü belirsiz
GET  /auth/me/commerce/purchases
GET  /auth/me/commerce/sales
```

**Etkilenen dosyalar:**
- `backend/app/routers/listings.py`
- `backend/app/routers/auth.py`
- `backend/app/schemas/listing.py` — `ListingOut` + `ListingDetailOut` (yeni şemalar)

**1. `ListingOut` (feed kartı için slim — TASK-yeni-N ile uyumlu):**
```python
# schemas/listing.py
from decimal import Decimal
from pydantic import BaseModel
from typing import Optional

class SellerMiniOut(BaseModel):
    id: int
    username: str
    avatar_url: Optional[str] = None
    is_premium: bool = False
    is_verified: bool = False
    badge: Optional[str] = None

    model_config = {"from_attributes": True}

class ListingOut(BaseModel):  # feed kartı
    id: int
    title: str
    price: Optional[Decimal] = None
    image_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    province: Optional[str] = None
    status: str
    is_highlight: bool = False
    likes_count: int = 0
    is_liked: bool = False
    is_sponsored: bool = False
    campaign_id: Optional[int] = None
    is_trending: bool = False
    user: SellerMiniOut

    model_config = ConfigDict(from_attributes=True, json_encoders={Decimal: float})
    # TASK-04 tamamlanınca BaseSchema'dan türet — json_encoders={Decimal: float} gereksiz kalır

class ListingDetailOut(ListingOut):  # detay ekranı — ListingOut'u genişletir
    description: Optional[str] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    brand: Optional[str] = None
    condition: Optional[str] = None
    extra_fields: Optional[dict] = None
    image_urls: list[str] = []
    video_url: Optional[str] = None
    district: Optional[str] = None
    location: Optional[str] = None
    buy_it_now_price: Optional[Decimal] = None
    impression_count: int = 0
    is_favorited: bool = False
    expires_at: Optional[str] = None
```

**2. Router'lara ekle:**
```python
# routers/listings.py
@router.get("", response_model=list[ListingOut])
async def get_listings(...): ...

@router.get("/{listing_id}", response_model=ListingDetailOut)
async def get_listing(...): ...
```

**3. `/auth/me` zaten `UserOut` var — sadece ekle:**
```python
@router.get("/me", response_model=UserOut)  # ← ekle, şema zaten mevcut
```

**4. `/auth/init` ve `/auth/me/commerce/*` — ne döndürdüğünü incele, mevcut dict yapısına uygun şema oluştur.**

> **Önemi:** `response_model=` eklenmesi = Pydantic validation açılır + `hashed_password`/`is_shadowbanned`/`preference_embedding` alanları otomatik filtrelenir. Sıfır müşteri etkisi, maksimum güvenlik.

**Test:**
- `GET /listings` → JSON field listesi `ListingOut` alanlarıyla eşleşiyor
- `hashed_password` hiçbir response'da görünmüyor
- `GET /auth/me` → `UserOut` alanlarının dışında alan yok

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-A · P5c · 🔴 D7: listing_offers — status alanı ekle

**Plan:** Faz 2.2 D7  
**Sorun:** `listing_offers` tablosunda `status` alanı yok. GC3 cleanup'ı `WHERE status IN ('declined','expired')` filtresini kullanamıyor. Ayrıca ilana gelen tekliflerin kabul/reddedilme durumu takip edilemiyor.

**Etkilenen dosyalar:**
- `backend/app/models/listing_offer.py` — status alanı ekle
- `backend/alembic/versions/` — Migration
- `backend/app/use_cases/listings/commands/create_offer.py` — default status
- İlgili komutlar: accept_offer, decline_offer use case (varsa)

**Uygulama:**
1. Model güncelle:
   ```python
   from sqlalchemy import String
   status: Mapped[str] = mapped_column(String(20), nullable=False, default="active", server_default="active")
   updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True, onupdate=func.now())
   ```
2. Alembic migration:
   ```python
   op.execute("ALTER TABLE listing_offers ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active'")
   op.execute("ALTER TABLE listing_offers ADD COLUMN updated_at TIMESTAMPTZ")
   ```
3. GC3 cleanup sorgusunu güncelle (`WHERE status IN ('declined','expired') AND created_at < ...`)

**Test:**
- Yeni teklif → status="active"
- Reddedilen teklif → status="declined"
- GC3: sadece declined/expired/active-ve-eski teklifler temizleniyor

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-C · P5e · 🟡 DM Raporlama — flag_reason Aktivasyonu

**Plan:** Faz 2.2  
**Sorun:** `direct_messages.flag_reason VARCHAR(255)` kolonu var ama hiçbir endpoint bu kolonu set etmiyor. Kullanıcılar mesajları raporlayamıyor; moderasyon sırası oluşturulamıyor.

**Mevcut altyapı:** `backend/app/routers/reports.py` — ilan raporlama için mevcut. DM raporlama bu router'a endpoint olarak eklenir.

**Etkilenen dosyalar:**
- `backend/app/routers/messages.py` — `POST /{message_id}/flag` endpoint ekle
- `backend/app/models/message.py` — `flag_reason` zaten var, değişiklik yok
- `backend/alembic/versions/` — Migration yok (kolon zaten mevcut)
- `mobile/lib/` — DM ekranında mesaj uzun basma menüsüne "Raporla" seçeneği (MVVM)

**Backend uygulama (Clean Architecture — Router → Use Case → Repository):**
```python
# backend/app/use_cases/messages/commands/flag_message.py — YENİ DOSYA
class FlagMessageCommand:
    def __init__(self, uow):
        self.uow = uow

    async def execute(self, message_id: int, reason: str, requester_id: int) -> None:
        async with self.uow as uow:
            msg = await uow.db.get(DirectMessage, message_id)
            if not msg:
                raise AppException(status_code=404, code="NOT_FOUND")
            if msg.receiver_id != requester_id:
                raise AppException(status_code=403, code="FORBIDDEN")
            msg.flag_reason = reason
            await uow.db.commit()

# backend/app/routers/messages.py — Router yalnızca delegasyon yapar
@router.post("/{message_id}/flag", status_code=204)
async def flag_message(
    message_id: int,
    reason: str,   # "spam" | "harassment" | "inappropriate" | "scam" | "other"
    uow=Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    await FlagMessageCommand(uow).execute(message_id, reason, current_user.id)
```

**Flutter (MVVM):**
- `DirectMessageViewModel.flagMessage(messageId, reason)` — `POST /messages/{id}/flag`
- DM ekranında mesaj baloncusuna uzun basınca: "Raporla" seçeneği → reason seçici bottom sheet
- `mobile/lib/services/message_service.dart` veya ViewModel'e method ekle

**Test:**
- Mesaj al → uzun bas → Raporla → reason seç → 204 döner
- `SELECT flag_reason FROM direct_messages WHERE id=...` → reason kaydedildi
- Başka kullanıcının mesajını raporlamaya çalış → 403

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-D · P5f · 🟡 Search Alert Trigger + Flutter Feed Stats

**Plan:** Faz 2.2  
**Sorun:**
1. `search_alerts` tablosu ve CRUD endpoint'leri var, kullanıcılar alert oluşturabiliyor — ama yeni ilan eklenince bildirim gönderen mekanizma hiç implemente edilmemiş.
2. `analytics_service.dart:getFeedStats()` tanımlı, backend `GET /analytics/my-feed-stats` aktif — ama Flutter'da hiçbir ekran bu metodu çağırmıyor.

---

**1. Search Alert ARQ Worker Task (Backend):**

Etkilenen dosyalar:
- `backend/app/worker.py` — yeni cron görev

```python
async def check_search_alerts_task(ctx: dict) -> None:
    """
    Son 15 dakikada eklenen ilanları aktif search_alert'larla eşleştirir.
    Eşleşen alert sahibine push bildirim gönderir.
    """
    # Doğru import: worker.py'deki mevcut pattern (satır 2282, 2692 vb.)
    from app.routers.notifications import push_notification

    async with AsyncSessionLocal() as db:
        # Son 15 dakikada aktif olan yeni ilanlar
        since = datetime.now(timezone.utc) - timedelta(minutes=15)
        new_listings = await db.execute(
            select(Listing).where(
                Listing.status == "active",
                Listing.created_at >= since,
            )
        )
        listings = new_listings.scalars().all()
        if not listings:
            return

        # Tüm aktif alert'ları çek
        alerts = (await db.execute(
            select(SearchAlert).where(SearchAlert.status == SearchAlertStatus.ACTIVE)
        )).scalars().all()

        for listing in listings:
            for alert in alerts:
                if alert.user_id == listing.user_id:
                    continue  # Kendi ilanı için bildirim gönderme
                # Kategori eşleşmesi
                if alert.category and alert.category != listing.category:
                    continue
                # Fiyat filtresi
                if alert.max_price and listing.price and listing.price > alert.max_price:
                    continue
                # Metin eşleşmesi (title)
                if alert.query and alert.query.lower() not in (listing.title or "").lower():
                    continue
                # Eşleşti — bildirim gönder
                await push_notification(
                    alert.user_id,
                    {
                        "type": "search_alert",
                        "listing_id": listing.id,
                        "listing_title": listing.title,
                        "listing_price": float(listing.price) if listing.price else None,  # Decimal→float JSON için
                        "alert_query": alert.query or alert.category,
                    },
                    pref_key="search_alert",
                )
                # Not: listing.price TASK-04 sonrası Decimal olacak; float() burada JSON serileştirme için gerekli

# Cron: Her 15 dakikada bir
cron(check_search_alerts_task, minute={0, 15, 30, 45})
```

> **Not:** Ölçek büyüdüğünde cursor tabanlı (son işlenen `listing_id` Redis'te) yaklaşıma geçilebilir. Şimdilik `created_at >= since` yeterli.

---

**2. Flutter Feed Stats Ekranı:**

Etkilenen dosyalar:
- `mobile/lib/services/analytics_service.dart` — `getFeedStats()` zaten tanımlı, implement et
- `mobile/lib/screens/` — Pro satıcı profil veya ilan yönetim ekranında feed stats bölümü (MVVM)

```dart
// analytics_service.dart:getFeedStats() — backend: GET /api/analytics/my-feed-stats?days=7
// Response: impression, click, skip, CTR, dwell_time — sadece premium kullanıcılar
// Flutter: ViewModel.fetchFeedStats(days) → AsyncNotifier → feed stats widget
```

**Test:**
- Yeni ilan ekle (category+query eşleşen alert sahibi var) → 15 dk içinde bildirim geldi
- Kendi ilanın için bildirim gelmiyor
- Premium kullanıcı feed stats ekranı açılıyor, 7/30/90 günlük veri görünüyor
- Normal kullanıcı için premium engeli gösteriliyor

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-B · P5d · 🟡 D8: user_interests UNIQUE constraint düzelt

**Plan:** Faz 2.2 D8 · ADR §3.2  
**Sorun:** `UNIQUE(user_id, category)` subcategory-level kayıt eklenmesini engelliyor. `compute_user_interests_task`'ın upsert SQL'i de sadece `ON CONFLICT (user_id, category)` kullanıyor — subcategory desteği bozuk.

**Etkilenen dosyalar:**
- `backend/app/models/user_interest.py` — UniqueConstraint değiştir
- `backend/app/worker.py` — upsert SQL güncelle (subcategory dahil)
- `backend/alembic/versions/` — Migration

**Uygulama:**
1. Migration:
   ```python
   # Eski constraint'i düşür
   op.execute("ALTER TABLE user_interests DROP CONSTRAINT uq_user_interest")
   # Yeni: (user_id, category, subcategory) — subcategory NULL için NULLS NOT DISTINCT
   op.execute("""
       ALTER TABLE user_interests
       ADD CONSTRAINT uq_user_interest
       UNIQUE NULLS NOT DISTINCT (user_id, category, subcategory)
   """)
   ```
   > `NULLS NOT DISTINCT` (PG 15+): NULL değerler eşit sayılır → `(uid, 'cat', NULL)` ile `(uid, 'cat', NULL)` çakışır ama `(uid, 'cat', NULL)` ile `(uid, 'cat', 'phones')` çakışmaz.
   > PG 15 öncesi: partial index (`WHERE subcategory IS NULL`) + normal unique index (`WHERE subcategory IS NOT NULL`) kombinasyonu gerekir.

2. Model güncelle:
   ```python
   UniqueConstraint("user_id", "category", "subcategory", name="uq_user_interest")
   ```

3. Worker.py upsert için subcategory parametresi opsiyonel olarak ekle (mevcut category-level upsert korunur, subcategory entryler için ayrı upsert).

**Test:**
- `(user_id=1, category='electronics', subcategory=NULL)` ve `(user_id=1, category='electronics', subcategory='phones')` aynı anda tabloda olabiliyor
- Aynı kategori/subcategory çifti tekrar eklenince UPDATE yapıyor (insert değil)

**Node ops:** `alembic upgrade head` — migration non-blocking

**Status:** [ ] BEKLEMEDE

---

## Orta Öncelik Sprint — P16–P20

---

### TASK-16 · P16 · 🟢 GC2: calls cleanup görevi

**Plan:** Faz 1.4 · R2=2 yıl

**Uygulama:**
```python
async def cleanup_old_calls_task(ctx):
    async with AsyncSessionLocal() as db:
        result = await db.execute(text(
            "DELETE FROM calls WHERE status IN ('ended','missed') "
            "AND ended_at < NOW() - INTERVAL '730 days'"
        ))
        await db.commit()

cron(cleanup_old_calls_task, weekday=4, hour=4, minute=0)  # Perşembe 04:00
```

**Status:** [ ] BEKLEMEDE

---

### TASK-17 · P18 · 🟡 KV1: ip_address Maskeleme (KVKK)

**Plan:** Faz 9.2  
**Etkilenen dosyalar:**
- `backend/app/routers/analytics.py` veya middleware — IP kaydı yapılan yer

**Uygulama:**
```python
def mask_ip(ip: str) -> str:
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.0"
    return ip  # IPv6 için şimdilik saklama

# analytics event kaydedilmeden önce:
masked = mask_ip(request.client.host)
```

**Test:**
- Yeni analytics event kaydı → ip_address son okteti 0

**Status:** [ ] BEKLEMEDE

---

### TASK-18 · P19/P20 · 🟢 GC6/GC7 + D1 image_urls JSONB

**Plan:** Faz 1.4 (GC6/GC7) + Faz 2.2 (D1)

**GC6/GC7 (worker.py):**
```python
async def cleanup_empty_message_threads_task(ctx):
    async with AsyncSessionLocal() as db:
        # message_threads tablosunda (user_a_id, user_b_id) PK var — thread_id kolonu yok
        # status != 'pending' zorunlu — onay bekleyen DM isteklerini silmemek için
        # (auth.py:406 login'de pending request'leri listeler; silinirse istek kaybolur)
        await db.execute(text(
            "DELETE FROM message_threads mt "
            "WHERE mt.status != 'pending' "
            "AND NOT EXISTS ("
            "  SELECT 1 FROM direct_messages dm "
            "  WHERE (dm.sender_id = mt.user_a_id AND dm.receiver_id = mt.user_b_id) "
            "     OR (dm.sender_id = mt.user_b_id AND dm.receiver_id = mt.user_a_id)"
            ") AND mt.created_at < NOW() - INTERVAL '30 days'"
        ))
        await db.commit()

async def cleanup_inactive_search_alerts_task(ctx):
    # search_alerts'ta updated_at YOKTUR — created_at kullanılmalı
    async with AsyncSessionLocal() as db:
        await db.execute(text(
            "DELETE FROM search_alerts WHERE created_at < NOW() - INTERVAL '180 days'"
        ))
        await db.commit()

cron(cleanup_empty_message_threads_task, weekday=6, hour=5, minute=0)  # Paz 05:00
cron(cleanup_inactive_search_alerts_task, weekday=6, hour=6, minute=0) # Paz 06:00
```

**D1: listings.image_urls → JSONB:**
```python
# Alembic migration
op.execute("ALTER TABLE listings ALTER COLUMN image_urls TYPE JSONB USING image_urls::JSONB")
op.execute("CREATE INDEX ix_listings_image_urls_gin ON listings USING GIN (image_urls)")
```
- Model: `image_urls: Mapped[list] = mapped_column(JSONB)`
- Pydantic schema: `image_urls: list[str]`
- `bump_schema_version()` ekle

**Status:** [ ] BEKLEMEDE

---

## Düşük Öncelik Sprint — P21–P25

---

### TASK-18b · P20b · 🟡 listings.updated_at — Write Path Düzeltmesi

**Plan:** Faz 2.5  
**Sorun:** `listings.updated_at` her zaman NULL. `onupdate` yok, hiçbir update use case bu kolonu set etmiyor. API yanıtı `updated_at: null` dönüyor — yanıltıcı.

**Etkilenen dosyalar:**
- `backend/app/models/listing.py` — `onupdate=func.now()` ekle
- `backend/app/use_cases/listings/commands/update_listing.py` — explicit set ekle
- `backend/alembic/versions/` — Backfill migration

**Uygulama:**
1. Model:
   ```python
   updated_at: Mapped[Optional[datetime]] = mapped_column(
       DateTime(timezone=True), nullable=True,
       onupdate=func.now()
   )
   ```
2. `update_listing.py`'de update sonrası `listing.updated_at = func.now()` veya ORM flush tetikler.
3. Backfill migration:
   ```python
   op.execute("UPDATE listings SET updated_at = created_at WHERE updated_at IS NULL")
   ```

**Test:**
- İlan güncelle → `updated_at` NULL değil, şu anki zaman

**Status:** [ ] BEKLEMEDE

---

### TASK-18c · P20c · 🟢 listing.location Write Path Fix + ringing_at Aktivasyonu

**Plan:** Faz 2.5  

> `states.country_code` bu scope'tan **çıkarıldı** — multi-country entegrasyonunda kullanılacak (Faz 2.6).  
> `flag_reason` bu scope'tan **çıkarıldı** — DM raporlama özelliği olarak TASK-yeni-C'de implemente ediliyor.

---

**1. listing.location Write Path Fix:**

> **Sorun:** Flutter `location` alanını gönderiyor ve gösteriyor — ama backend `create_listing` ve `update_listing` use case'lerinde bu alanı hiç DB'ye yazmıyor. Kullanıcının girdiği konum sessizce kayboluyor.

Etkilenen dosyalar:
- `backend/app/use_cases/listings/commands/create_listing.py` — `location` parametresini al, modele yaz
- `backend/app/use_cases/listings/commands/update_listing.py` — `location` güncellemesini ekle
- `backend/app/routers/listings.py` — request body'de `location` alanının varlığını kontrol et

```python
# create_listing.py — listing oluşturulurken:
listing = Listing(
    ...
    location=data.location,   # ← ekle
)

# update_listing.py — listing güncellenirken:
if data.location is not None:
    listing.location = data.location  # ← ekle
```

---

**2. ringing_at Aktivasyonu:**

> **Sorun:** `call_participants.ringing_at` kolonu var ama hiçbir yerde set edilmiyor. Grup çağrısında davet edilen katılımcının zil çalmaya başladığı anı kaydetmek için kullanılmalı.
>
> **Mimari not:** 1-1 aramada `ringing` durumu Redis presence'da (`set_presence(..., "ringing", ...)`) tutuluyor — DB'ye yazılmıyor. `CallParticipant` yalnızca **grup çağrısı davetlileri** için var. Bu yüzden `ringing_at`, `CallParticipant` oluşturulduğu anda (davet push'u gönderildiğinde) set edilmeli.

Etkilenen dosya:
- `backend/app/routers/calls.py:1294` — `CallParticipant(...)` oluşturulurken `ringing_at=now` ekle

```python
# calls.py satır 1291-1302:
now = datetime.now(timezone.utc)
cp = CallParticipant(
    call_id=call_id,
    user_id=invitee_id,
    role="guest",
    status="invited",
    invited_by=current_user.id,
    livekit_token=livekit_token,
    invited_at=now,
    ringing_at=now,   # ← ekle — davet = zil başlangıcı
)
```

**Ne sağlar:** `ringing_at` ile `invited_at` farklı mı? Şu an aynı anda set ediliyor. İleride ACK tabanlı gerçek ring-start tespiti yapılırsa ayrışabilir. Şimdilik `invited_at` ile başlat yeterli.

---

**Test:**
- Flutter'dan `location` dolu ilan oluştur → `SELECT location FROM listings WHERE id=...` → değer kaydedildi
- İlan güncelle → location değişti
- Grup çağrısına davet gönder → `SELECT ringing_at FROM call_participants WHERE ...` → timestamp var

**Status:** [ ] BEKLEMEDE

---

### TASK-18d · ~~P20d~~ · ⏸️ countries Tablosu — BIRAKILDI

**Plan:** Faz 2.6 (Gelecek Kullanım)  
**Karar:** `countries` tablosu silinmeyecek. Çok ülke desteği (multi-country) eklendiğinde kullanılacak.

**Mevcut durum:**
- `countries(code, name)` — tablo var, seed data var
- `states.country_code VARCHAR(2)` — var ama FK bağlantısı yok, sorgu filtresi yok
- `/states` router yalnızca Türkiye illerini döndürüyor (ülke filtresi yok)
- Flutter `StateService` ülke seçici içermiyor

**Pazar izolasyonu aktivasyon sırası (zaman gelince):**
1. `users` tablosuna `country_code VARCHAR(2)` ekle — kullanıcının pazarı (TR/AZ/DE…)
2. `listings` tablosuna `country_code VARCHAR(2)` ekle — ilanın pazarı; backfill ile mevcut ilanları TR'ye set et
3. Feed/arama sorgularına `WHERE country_code = :user_market` filtresi ekle
4. Migration: `ALTER TABLE states ADD CONSTRAINT fk_states_country FOREIGN KEY (country_code) REFERENCES countries(code)`
5. States router'a `?country=TR` filtresi ekle
6. Flutter `StateService.getStates()` → ülke parametresi al; ilan oluşturma ekranına ülke seçici ekle
7. `exchange_rates` (usd_try, eur_try) üzerinden AZN/EUR fiyat gösterimi

> `states.country_code` adres seçicinin alt yapısı. Pazar izolasyonunun kendisi `users.country_code` + `listings.country_code`'a bağlı.

**Status:** ⏸️ BIRAKILDI — multi-country sprint'ine ertelendi

---

### TASK-18e · P20e · 🟡 Flutter User Model — Sosyal URL Typed Alanlar

**Plan:** Faz 2.5  
**Sorun:** `website_url`, `instagram_url`, `kick_url`, `twitch_url`, `facebook_url`, `youtube_url`, `tiktok_url` — `User` model sınıfında tip güvensiz `Map<String, dynamic>` erişimi ile kullanılıyor. `User.fromJson` kapsamı dışında.

**Etkilenen dosyalar:**
- `mobile/lib/models/user.dart` — Yeni opsiyonel alanlar
- `mobile/lib/screens/profile_screen.dart` — raw map erişimini typed alanlara taşı
- `mobile/lib/screens/public_profile_screen.dart` — aynı

**Uygulama:**
```dart
// User class'ına ekle
final String? websiteUrl;
final String? instagramUrl;
final String? kickUrl;
final String? twitchUrl;
final String? facebookUrl;
final String? youtubeUrl;
final String? tiktokUrl;

// fromJson:
websiteUrl: json['website_url'] as String?,
instagramUrl: json['instagram_url'] as String?,
// ...
```

**Test (MVVM):**
- Profil ekranında sosyal URL'ler doğru parse ediliyor
- `dart analyze` 0 hata

**Status:** [ ] BEKLEMEDE

---

### TASK-18f · P20f · 🟢 Flutter Dead Code Temizliği

**Plan:** Faz 2.5

**Kapsam:**
1. `mobile/lib/screens/teq_test_screen.dart` — Sil; `main.dart:17` import ve `main.dart:197` `/teq-test` route'unu kaldır (design system showcase ekranı, production özelliği yok)

> `getFeedStats()` bu scope'tan **çıkarıldı** — Flutter'da implement edilecek (TASK-yeni-D ile birlikte veya ayrı sprint'te).

**Dikkat:** `teq_test_screen.dart` içeriği incelendi — sadece TeqButton, TeqCard vb. UI component'leri gösteriyor, credential/debug verisi yok.

**Test:**
- `dart analyze` 0 hata
- Uygulama normal başlıyor

**Status:** [ ] BEKLEMEDE

---

### TASK-19 · P21 · 🟢 Medya Optimizasyonu (M1-M4)

**Plan:** Faz 8.2  
**Strateji:** Client-side encode, server passthrough. Sıkıştırma yükü Flutter'da; backend aldığını saklar, geri verir.  
**Referans cihaz:** iPhone 15 Pro (48 MP HEIC, 4K ProRes) — `flutter_image_compress` HEIC → WebP dönüşümü handle eder.

> `MediaCompressor` + `flutter_image_compress` + `video_compress` **zaten kurulu** — yalnızca parametre ve tür değişikliği.

**Kararlar:**

| # | Değişiklik | Onay |
|---|-----------|------|
| M1 | İlan fotoğrafı: JPEG 1200px q80 → WebP 1920px q80; max **3 fotoğraf** (şu an 10) | ✅ |
| M2 | İlan videosu: `HighestQuality` (1080p re-encode) → `MediumQuality` (720p H.264 scale) | ✅ |
| M3 | DM medya limitleri: Foto 5→3 MB, Video 30→20 MB | ✅ |
| M4 | Profil fotoğrafı: `dmPhoto` türü (1200px JPEG) → yeni `profilePhoto` türü (800px WebP q75) | ✅ |

---

**Etkilenen dosyalar:**
- `mobile/lib/services/media_compressor.dart` — M1/M2/M4
- `mobile/lib/core/media_constants.dart` — M3
- `mobile/lib/screens/create_listing_screen.dart:98` — M1 (max 3 fotoğraf)
- `mobile/lib/screens/profile_screen.dart:2471` — M4 (tür değişikliği)
- `backend/app/constants/media_limits.py` — M3

---

**M1 — İlan fotoğrafı (media_compressor.dart):**
```dart
// _compressPhoto metoduna format parametresi ekle:
static Future<CompressedMedia> _compressPhoto(
  String inputPath, int originalBytes, {
  required int maxDim,
  required int quality,
  CompressFormat format = CompressFormat.jpeg,
}) async {
  final result = await FlutterImageCompress.compressWithFile(
    inputPath,
    minWidth: maxDim, minHeight: maxDim,
    quality: quality,
    format: format,
    keepExif: false,
  );
  return CompressedMedia(
    bytes: result!,
    mimeType: format == CompressFormat.webp ? 'image/webp' : 'image/jpeg',
    extension: format == CompressFormat.webp ? 'webp' : 'jpg',
    originalBytes: originalBytes,
    compressedBytes: result.length,
  );
}

// listingPhoto case güncelle:
case MediaCompressType.listingPhoto:
  return _compressPhoto(inputPath, originalBytes,
    maxDim: 1920, quality: 80, format: CompressFormat.webp);

// M4 — profilePhoto yeni case:
case MediaCompressType.profilePhoto:
  return _compressPhoto(inputPath, originalBytes,
    maxDim: 800, quality: 75, format: CompressFormat.webp);
```

**MediaCompressType enum'a ekle:**
```dart
enum MediaCompressType {
  voice, dmVideo, dmPhoto, listingPhoto, listingVideo,
  storyPhoto, storyVideo,
  profilePhoto,  // ← yeni — M4
}
```

**M2 — İlan videosu (media_compressor.dart):**
```dart
// listingVideo case:
// ÖNCE: quality: VideoQuality.HighestQuality  (1080p re-encode, ağır)
// SONRA: quality: VideoQuality.MediumQuality  (720p H.264, ~15-25s iPhone 15 Pro'da)
case MediaCompressType.listingVideo:
  return _compressVideo(inputPath, originalBytes,
    quality: VideoQuality.MediumQuality,
    onProgress: onProgress);
```

> iPhone 15 Pro: 1 dk 4K video → MediumQuality (720p H.264) → ~20-35 MB, A17 Pro'da ~15-25s.  
> Server: `-c:v copy` korunur (zaten client sıkıştırdı).

**M1 — Max 3 fotoğraf (create_listing_screen.dart:98):**
```dart
// ÖNCE: static const int _maxImages = 10;
// SONRA:
static const int _maxImages = 3;
```

**M3 — DM limitleri (media_constants.dart + media_limits.py):**
```dart
// media_constants.dart:
static const int imageMaxBytes = 3 * 1024 * 1024;   // 5 MB → 3 MB
static const int videoMaxBytes = 20 * 1024 * 1024;  // 30 MB → 20 MB
```
```python
# media_limits.py:
IMAGE_MAX_BYTES = 3 * 1024 * 1024   # 5 MB → 3 MB
VIDEO_MAX_BYTES = 20 * 1024 * 1024  # 30 MB → 20 MB
```

**M4 — Profil fotoğrafı (profile_screen.dart:2471):**
```dart
// ÖNCE: MediaCompressType.dmPhoto  (1200px JPEG — yanlış tür kullanılıyordu)
// SONRA:
final compressed = await MediaCompressor.compress(
  picked.path, MediaCompressType.profilePhoto);
final upload = await ref.read(uploadServiceProvider).uploadBytes(
  Uint8List.fromList(compressed.bytes), 'avatar.webp');
```

---

**Tahmini depolama kazancı (iPhone 15 Pro referansı):**

| Medya | Öncesi | Sonrası |
|-------|--------|---------|
| İlan fotoğrafı (48 MP HEIC ~15 MB) | ~5 MB JPEG 1200px | ~300 KB WebP 1920px |
| İlan videosu (1 dk 4K ~350 MB) | ~30-50 MB 1080p | ~20-35 MB 720p |
| Profil avatarı (2-5 MB) | ~1.2 MB JPEG 1200px | ~60 KB WebP 800px |

---

**Test:**
- iPhone 15 Pro veya yüksek MP Android ile ilan oluştur: 3'ten fazla fotoğraf eklenemiyor
- Fotoğraf upload → MinIO'da `.webp` uzantılı dosya var
- 1 dk video compress süresi makul (< 30s)
- Avatar güncelle → MinIO'da `avatar.webp` var
- DM'de 3 MB'ı aşan fotoğraf → hata gösteriliyor

**Node ops:** Yok (sadece Flutter + backend constants değişikliği)

**Status:** [ ] BEKLEMEDE

---

### TASK-20 · P22 · 🟢 Hesap Silme Akışı (KVKK/GDPR)

**Plan:** Faz 9.1 + R11=■

**Etkilenen dosyalar:**
- `backend/app/routers/users.py` — `DELETE /users/me` endpoint (yeni)
- `backend/app/use_cases/user_use_cases.py` — Anonimleştirme use case (Clean Architecture)
- `backend/app/repositories/user_repository.py` — Soft-delete + NULL set
- `backend/app/services/storage_service.py` — MinIO avatar silme (node1/node4)

**Anonimleştirme use case (Clean Architecture):**
```python
# backend/app/use_cases/users/commands/delete_account.py
class DeleteAccountCommand:
    def __init__(self, uow, storage_service):
        self.uow = uow
        self.storage = storage_service

    async def execute(self, user_id: int) -> None:  # int — UUID değil, sistem int PK kullanıyor
        async with self.uow as uow:
            await uow.user_repo.anonymize(user_id)       # email/phone/full_name → NULL/placeholder
            await uow.dm_repo.anonymize_sender(user_id)  # sender_id NULL
            await uow.db.commit()
        await self.storage.delete_avatar(user_id)        # MinIO — DB commit sonrası
        # purchases/tuci_transactions: KORUNUR (TTK md.82 mali kayıt yükümlülüğü)
        # analytics_events.user_id: FK SET NULL varsa otomatik, yoksa ayrı NULL set
```

**Flutter (MVVM):**
- `ProfileViewModel.deleteAccount()` → backend endpoint'ini çağırır
- View: onay dialog → ViewModel çağrısı → logout
- ⚠️ **Endpoint çelişkisi:** Flutter `auth_service.dart:219` şu an `DELETE /auth/delete-account` çağırıyor; task.md `DELETE /users/me` öneriyor. Uygulama sırasında backend hangi path'i implement ederse Flutter'ı ona göre güncelle (veya mevcut `/auth/delete-account` path'ini koru — backend önce kontrol et).

**Status:** [ ] BEKLEMEDE

---

### TASK-21 · P23 · 🟢 D2/D4/D5 Model Düzeltmeleri

**Plan:** Faz 2.2

| # | Düzeltme |
|---|---------|
| D2 | `listings.active_room_id`: FK `ForeignKey("live_streams.id", ondelete="SET NULL")` ekle |
| D4 | `reports.created_at`: `DateTime(timezone=True), server_default=func.now()` |
| D5 | `app_configs.updated_at`: `DateTime(timezone=True)` |

**Etkilenen dosyalar:**
- `backend/app/models/listing.py`
- `backend/app/models/report.py`
- `backend/app/models/app_config.py`
- `backend/alembic/versions/` — Migration

**Status:** [ ] BEKLEMEDE

---

### TASK-22 · P24 · 🟢 KV2/KV3 — KVKK Tamamlama

**Plan:** Faz 9.2

| # | Değişiklik |
|---|-----------|
| KV2 | `DELETE /users/me` — TASK-20 ile birlikte |
| KV3 | `notification_prefs`'e `analytics_opt_out: bool` ekle |

**KV3 uygulama:**
- Migration: `notification_prefs JSONB` alanına yeni key ekle veya users tablosuna `analytics_opt_out BOOLEAN DEFAULT FALSE`
- Analytics event kaydında kontrol: `if not user.analytics_opt_out`
- Flutter: Ayarlar ekranında toggle (MVVM — `SettingsViewModel.toggleAnalyticsOptOut()`)

**Status:** [ ] BEKLEMEDE

---

### TASK-23 · P25 · 🟢 tuci → teqlik Yeniden Adlandırma

**Plan:** Faz 10  
**Bağımlılık:** Tüm önceki tasklar tamamlanmış olmalı.

**Kapsam:**
- `tuci_transactions` → `teqlik_transactions` (Alembic migration: RENAME TABLE)
- `users.tuci_balance` → `users.teqlik_balance` (Alembic: RENAME COLUMN)
- Python: model, repository, use_case, schema, worker.py
- API JSON response: `tuci_balance` → `teqlik_balance`
- Flutter: **9+ dosya** etkilenecek (4 değil):
  1. `providers/ai_desc_provider.dart` — `tuciSpent`/`tuci_spent`
  2. `screens/retargeting_screen.dart` — `tuci_balance`, `spent_tuci`, `tuciBalance`, `tuciCost` (10+ satır)
  3. `screens/profile_screen.dart` — `state.tuciBalance`
  4. `screens/listing_detail_screen.dart` — `tuciBalance`, `tuci_balance` JSON key, `TUCi` string
  5. `screens/viewmodels/profile_view_model.dart` — `tuciBalance`, `tuciHistory`
  6. `screens/create_listing_screen.dart` — `next.tuciSpent`, `'tuciSpent'` i18n key
  7. `utils/start_stream_helper.dart` — `TUCi` UI string
  8. `screens/live_stream_analytics_screen.dart` — `TUCi` UI string
  9. `screens/live_stream_history_screen.dart` — `TUCi` UI string

**Geçiş stratejisi:**
1. Backend: Eski alan adlarını Pydantic `alias` ile 1 sprint geç destekle
2. Flutter güncellendikten sonra alias kaldır

**Migration ek adımı:**
```python
# TASK-11'de oluşturulan index de güncellenmeli (TASK-11 bu tasktan önce uygulanmışsa):
op.execute("ALTER INDEX ix_tuci_transactions_user_created RENAME TO ix_teqlik_transactions_user_created")
```

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-N · P26 · 🟡 Ağ Katmanı Lightweight — Slim Feed DTO

**Plan:** Faz 5.1 ile birlikte (TASK-15 ile aynı sprint).  
**Hedef:** Listing feed payload boyutunu %30-40 azalt; kart görünümünde gereksiz alanlar gönderilmesin.

**Mevcut durum:**
- GZip: **Zaten aktif** — nginx (`gzip_comp_level 6`) + FastAPI (`GZipMiddleware(minimum_size=1000)`) ✅
- `listing_utils.py:_row_dict` → 30+ alan gönderiliyor (her feed ilanı için)
- Home screen kart: yalnızca ~12 alan kullanıyor (`id, title, price, image_url, thumbnail_url, province, status, is_highlight, is_liked, likes_count, is_sponsored, campaign_id, is_trending`, `user.badge`, `user.is_premium`)
- Search screen: `id, title, price, image_url, image_urls, subcategory, is_highlight, is_sponsored, active_room_id, video_url`, `user.*`
- 20 ilanlik feed ≈ gereksiz +40% payload

**Feed'de gönderilip kullanılmayan alanlar:**
`description`, `extra_fields`, `brand`, `condition`, `category`, `district`, `location`, `updated_at`, `deactivated_at`, `expires_at`, `buy_it_now_price`, `impression_count`, `is_favorited`, `user.trust_score`, `user.influence_rank`, `user.full_name`, `user.profile_image_thumb_url`

**Uygulama:**

**1. `listing_utils.py` — `_card_dict` slim fonksiyon ekle:**
```python
def _card_dict(
    listing: Listing,
    user: User,
    likes_count: int = 0,
    is_liked: bool = False,
    is_sponsored: bool = False,
    campaign_id: Optional[int] = None,
    seller_badge: Optional[str] = None,
    is_trending: bool = False,
    is_favorited: bool = False,
) -> dict:
    """Feed kartı için slim payload — detay ekranı _row_dict kullanır."""
    return {
        "id": listing.id,
        "title": listing.title,
        "price": listing.price,
        "image_url": listing.image_url,
        "thumbnail_url": listing.thumbnail_url,
        "province": listing.province,
        "status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status),
        "is_highlight": listing.is_highlight,
        "likes_count": likes_count,
        "is_liked": is_liked or is_favorited,
        "is_favorited": is_favorited or is_liked,
        "is_sponsored": is_sponsored,
        "campaign_id": campaign_id,
        "is_trending": is_trending,
        "user": {
            "id": user.id,
            "username": user.username,
            "avatar_url": user.profile_image_url,
            "is_premium": user.is_premium,
            "is_verified": user.is_verified,
            "badge": seller_badge,
        },
    }
```

**2. Feed endpoint'leri `_card_dict` kullansın:**
- `backend/app/use_cases/listings/queries/get_swipe_feed.py` — `_row_dict` → `_card_dict`
- `backend/app/use_cases/feed/queries/feed_queries.py` — `_row_dict` → `_card_dict`
- `backend/app/use_cases/listings/queries/search_listings_query.py` — search sonuçları için değerlendir (bazı alanlar gerekli olabilir)
- `backend/app/services/feed/listing_cache_service.py` — Redis cache'teki full payload sorununu değerlendir

**3. `GET /listings/{id}` (detay) `_row_dict` kullanmaya devam eder** — değişiklik yok.

**4. home_screen `seller_badge`/`seller_is_premium` mismatch:**
- Home screen `widget.listing['seller_badge']` ve `widget.listing['seller_is_premium']` erişiyor
- Backend `listing['user']['badge']` ve `listing['user']['is_premium']` gönderiyor
- Home screen kart build fonksiyonunu kontrol et: muhtemelen `listing['user']` map'ten okuyor ama `widget.listing['seller_*']` top-level erişim de var
- `_card_dict` içinde `user.badge` doğru yerde zaten — mismatch kaydedildi, Flutter tarafını gözlemle

**5. Flutter `image_urls` kart görünümü:**
- Home screen feed kartı `image_urls` listesine erişiyor ama yalnızca ilk kare gerekli
- `_card_dict` `image_urls` göndermez; Flutter'da `image_url` (tek URL) ve `thumbnail_url` yeterli
- Search screen `image_urls` kullanıyorsa ayrı `_search_dict` veya alan ekle

**Test:**
- `GET /api/feed` response body boyutunu ölç (curl + `wc -c`)
- 20 ilanlik feed: slim DTO `_card_dict` ile ~30-40% küçülme beklentisi
- Flutter kart görünümünde görsel kayıp yok
- Detay ekranı `_row_dict` ile tüm alanları alıyor

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-G · P27 · 🟡 S5/S6/S10: Pydantic Şema Konsolidasyonu

**Plan:** Faz 2.1 (TASK-yeni-F ile birlikte — şema ailesi)  
**Kaynak:** `findings.md §S5, §S6, §S10`

**Sorun:**
- **S5:** Aynı `users` tablosundan 4 ayrı şema: `UserOut (26 alan)`, `StoryAuthorOut (5)`, `BlockedUserOut (4)`, `StreamHostOut (3)` — ortak `UserMiniOut` base yok; alan ekleme → 4 dosya değiştirme.
- **S6:** `DirectSaleSummaryOut` 16 alanda seller ve buyer rollerini karıştırıyor — rol bazlı alanlar her zaman opsiyonel. Client tarafında boş null-check sarmalı.
- **S10:** `/conversations` ve `/requests` endpoint'leri aynı `ConversationOut` şemasını `is_request: bool` flag ile döndürüyor — discriminated union daha temiz.

**Etkilenen dosyalar:**
- `backend/app/schemas/user.py`
- `backend/app/schemas/story.py`
- `backend/app/schemas/stream.py` (StreamHostOut)
- `backend/app/schemas/direct_sale.py`
- `backend/app/schemas/message.py` (ConversationOut)

**1. `UserMiniOut` base şema:**
```python
# schemas/user.py — yeni ekleme
class UserMiniOut(BaseModel):
    id: int
    username: str
    full_name: str
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None
    is_verified: bool = False
    model_config = {"from_attributes": True}

# Türetilmiş şemalar (mevcut şemalar aynen korunur, base değişir):
class StoryAuthorOut(UserMiniOut):  # zaten aynı alanlar
    pass

class BlockedUserOut(UserMiniOut):  # subset — OK
    pass

class StreamHostOut(UserMiniOut):   # subset — OK
    pass
```

**2. `DirectSaleSummaryOut` discriminated union:**
```python
from typing import Literal, Union
from pydantic import BaseModel

class DirectSaleSummaryBase(BaseModel):
    sale_id: int
    item_name: str
    status: str
    proof_image_url: Optional[str] = None
    image_url: Optional[str] = None
    end_reason: Optional[str] = None
    ended_at: Optional[str] = None

class SellerSummaryOut(DirectSaleSummaryBase):
    role: Literal["seller"]
    total_revenue: Optional[float] = None
    total_quantity_sold: Optional[int] = None
    order_count: Optional[int] = None
    seller_username: str

class BuyerSummaryOut(DirectSaleSummaryBase):
    role: Literal["buyer"]
    buyer_quantity: int
    buyer_unit_price: float
    buyer_total: float
    buyer_order_status: str

DirectSaleSummaryOut = Annotated[Union[SellerSummaryOut, BuyerSummaryOut], Field(discriminator="role")]
```

**3. `ConversationOut` / `MessageRequestOut` ayrımı:**
```python
class ConversationOut(BaseModel):
    user_id: int; username: str; full_name: str
    last_message: str; last_at: str; unread_count: int
    last_message_type: str = "text"

class MessageRequestOut(ConversationOut):  # istek kuyruk flag yerine ayrı tür
    pass
# is_request: bool alanı kaldırılır; endpoint'ler farklı tip döndürür
```

**Test:**
- `GET /messages/conversations` → `is_request: bool` alanı yok
- `GET /direct-sales/{id}/summary` → role="seller" ise SellerSummaryOut, "buyer" ise BuyerSummaryOut
- StoryAuthorOut alanları UserMiniOut'tan geliyor
- `dart analyze` 0 hata (Flutter `User` model'ı etkilenmeyebilir — backend şema değişikliği)

**Status:** [ ] BEKLEMEDE

---

## Özet Tablosu

| Task | Öncelik | Sprint | Faz | Status |
|------|---------|--------|-----|--------|
| **— KRİTİK SPRINT —** | | | | |
| TASK-05 · PgBouncer | 🔴 P1 | Kritik | 3.1 | [ ] |
| TASK-01 · D3 auction status | 🔴 P2 | Kritik | 2.2 | [ ] |
| TASK-03 · GC1 stream viewers | 🔴 P3 | Kritik | 1.4 | [ ] |
| TASK-04 · Float→Numeric(12,2) | 🔴 P4 | Kritik | 2.1 | [ ] |
| TASK-02 · FK SET NULL (gift+bids+direct_sales+auctions) | 🔴 P5 | Kritik | 2.3 | [ ] |
| TASK-yeni-E · DM+Notif BigInt PK + DM retention | 🔴 P5g | Kritik | 2.1 | [ ] |
| TASK-yeni-F · response_model kritik endpoint'ler | 🔴 P5h | Kritik | 2.1 | [ ] |
| TASK-yeni-A · D7 listing_offers status | 🔴 P5c | Kritik | 2.2 | [ ] |
| TASK-yeni-B · D8 user_interests constraint | 🟡 P5d | Kritik | 2.2 | [ ] |
| TASK-yeni-C · DM raporlama (flag_reason) | 🟡 P5e | Kritik | 2.2 | [ ] |
| TASK-yeni-D · Search alert trigger + Flutter feed stats | 🟡 P5f | Kritik | 2.2 | [ ] |
| **— YÜKSEK ÖNCELIK —** | | | | |
| TASK-06 · ClickHouse TTL 365g | 🟡 P6 | Yüksek | 4.1 | [ ] |
| TASK-07 · user_interactions 365g | 🟡 P7 | Yüksek | 1.2 | [ ] |
| TASK-08 · MinIO lifecycle | 🟡 P8 | Yüksek | 1.5 | [ ] |
| TASK-09 · W1/W3/W4/W5 4x/gün | 🟡 P9 | Yüksek | 6.1 | [ ] |
| TASK-10 · W2/W6/W7 frekans | 🟡 P9b | Yüksek | 6.1 | [ ] |
| TASK-11 · Composite index'ler | 🟡 P10 | Yüksek | 3.2 | [ ] |
| TASK-12 · GC3/GC4/GC5 | 🟢 P11/P12 | Yüksek | 1.4 | [ ] |
| **— ORTA ÖNCELIK —** | | | | |
| TASK-13 · Keyset pagination | 🟡 P13 | Orta | 5.2 | [ ] |
| TASK-14 · Endpoint cache | 🟡 P14 | Orta | 5.3 | [ ] |
| TASK-15 · Feed N+1 fix | 🟡 P15 | Orta | 5.1 | [ ] |
| TASK-yeni-N · Slim feed DTO | 🟡 P26 | Orta | 5.1 | [ ] |
| TASK-yeni-G · Pydantic şema konsolidasyonu | 🟡 P27 | Orta | 2.1 | [ ] |
| TASK-16 · GC2 calls cleanup | 🟢 P16 | Orta | 1.4 | [ ] |
| TASK-17 · KV1 ip maskeleme | 🟡 P18 | Orta | 9.2 | [ ] |
| TASK-18 · GC6/GC7 + D1 JSONB | 🟢 P19/P20 | Orta | 1.4/2.2 | [ ] |
| TASK-18b · listings.updated_at write path | 🟡 P20b | Orta | 2.5 | [ ] |
| TASK-18c · listing.location + ringing_at | 🟢 P20c | Orta | 2.5 | [ ] |
| TASK-18d · countries — BIRAKILDI | ⏸️ | — | 2.6 | ⏸️ |
| TASK-18e · Flutter User sosyal URL typed | 🟡 P20e | Orta | 2.5 | [ ] |
| TASK-18f · Flutter dead code temizliği | 🟢 P20f | Orta | 2.5 | [ ] |
| **— DÜŞÜK ÖNCELIK —** | | | | |
| TASK-19 · Medya M1-M4 | 🟢 P21 | Düşük | 8.2 | [ ] |
| TASK-20 · Hesap silme KVKK | 🟢 P22 | Düşük | 9.1 | [ ] |
| TASK-21 · D2/D4/D5 model fix | 🟢 P23 | Düşük | 2.2 | [ ] |
| TASK-22 · KV2/KV3 opt-out | 🟢 P24 | Düşük | 9.2 | [ ] |
| TASK-23 · tuci→teqlik rename | 🟢 P25 | Düşük | 10 | [ ] |

---

## Gelecek Sprint Backlog — Kasıtlı Ertelenenler

> Aşağıdaki yapılar mevcut sprint'e dahil edilmedi. Silinmedi, ileride kullanılacak.

| Yapı | Niyet | Aktivasyon Şartı |
|------|-------|-----------------|
| **Pazar seçimi** (onaylı ürün yol haritası) — `countries`, `states.country_code`, `exchange_rates` hazır; `users.selected_market` + `listings.country_code` eksik | Kullanıcı pazar seçer (TR/AZ/DE…), feed+arama+fiyat değişir | Pazar sprint'i — 7 adım, plan.md Faz 2.6 |
| `referral.status = 'pending'` | İki adımlı referral: kayıt → pending; ilk alışveriş → completed + ödül tetikle | Referral iş mantığı sprint'i — `apply_referral` service refactor + ARQ görevi |
| `ad_campaigns` DB + API | Satıcı boost/reklam — schema ve wallet entegrasyonu var | Flutter "reklam ver" ekranı sprint'i — `create_listing_screen` boost butonu + reklam oluşturma akışı |
| **ClickHouse `init_clickhouse()` DB bug** — `database_clickhouse.py` `init_clickhouse()` tabloları `database` parametresi belirtmeden oluşturuyor → `default` DB'ye yazıyor (`findings.md §Gelecek`). `settings.clickhouse_db` ile bağlanmalı. | Şimdilik tabloları bootstrap'ta elle oluşturmak gerekiyor (operasyonel yük) | ClickHouse sprint'i — `init_clickhouse()` refactor + `settings.clickhouse_db` parametresi |
| **node4 bootstrap script** — `bootstrap_node4.sh` henüz yazılmamış. node1 ile aynı yapıda olacak. | node4 production edge node — script olmadan sıfırdan kurulamaz | Ops sprint'i — node1 bootstrap'ından türet |
| **S2 — DM OR sorgusu + thread_id** (`findings.md §S2`) — `direct_messages`'ta `thread_id` yok; `(sender_id=A AND receiver_id=B) OR (sender_id=B AND receiver_id=A)` çift Index Scan + BitmapOr. `message_threads`'e `id BIGINT` PK ekle, `direct_messages`'a `thread_id FK` ekle, sorguyu `thread_id = :id` equality'e taşı. | Büyük yapısal değişiklik — tüm message use case'leri etkilenecek | DM refactor sprint'i — `message_threads` + `direct_messages` model değişikliği, 4 adım |
| **S3 — `users` God Object** (`findings.md §S3`) — 47 kolon, 6 sorumluluk: kimlik + profil + sosyal + bildirim + GDPR + referral tek tabloda. `notification_prefs JSONB` tip güvensiz (14 alan JSON'da). | `users` tablosu WHERE koşulsuz SELECT'te ~47 kolon çeker; JOIN maliyeti yüksek | DB refactor sprint'i — `user_social_links` + `user_consents` ayrı tablolar; `notification_prefs` → `user_notification_prefs` tablo |
| **S7 — Flutter Freezed** (`findings.md §S7`) — 45+ Flutter modeli tamamen manuel `fromJson`; API alan değişikliği = runtime crash. `flutter_freezed` + `json_serializable` ile üretilmiş koda geçiş. | Büyük efor (~45 sınıf); her ekranı test etmek gerekiyor | Flutter refactor sprint'i — Freezed generator kurulumu + model-by-model migration |
| **S8 — ChatMessage tiplanmamış alanlar** (`findings.md §S8`) — `ChatMessage.announcementPayload: Map<String, dynamic>?` tip yok; yeni announcement tipi eklense crash. Sealed class'a çevrilmeli. | Chat panel etkilenecek — sealed + pattern matching | Flutter refactor sprint'i (S7 ile birlikte) |
| **S13 — `UserOut` 26 alan, 7 sosyal URL** (`findings.md §S13`) — Her response'da 7 boş sosyal medya URL taşınıyor. Backend: `UserOut` (core) + `UserProfileOut` (sosyal linkler dahil) ayrımı. Flutter tarafı TASK-18e ile zaten planlandı. | `schemas/user.py` + etkilenen router'lar; TASK-yeni-G `UserMiniOut` tamamlandıktan sonra | Schema refactor sprint'i — S5/S6 sonrası |
| **S15 — `StreamTokenOut` / `JoinTokenOut` örtüşmesi** (`findings.md §S15`) — İkisi de LiveKit bağlantı bilgisi, 5 ortak alan. Ortak `LiveKitTokenOut` base ile birleştirilebilir. | `schemas/stream.py` + ilgili endpoint'ler | Schema refactor sprint'i — az efor, bakım kolaylığı |
| **S11 — `AuctionStateOut` aşırı kullanım** (`findings.md §S11`) — 9 farklı endpoint 1 şemayı paylaşıyor; her auction state'inde farklı alanlar dolu/boş. Discriminated union daha temiz olur. | Auction iş mantığı büyüyünce tetikle — koşullu | Auction refactor sprint'i — `AuctionCreatedOut`, `AuctionActiveOut`, `AuctionEndedOut` ayrımı |
| **S12 — `StoryItemOut` iki tip, tek şema** (`findings.md §S12`) — `story_type='video'` → video alanları dolu; `'live_redirect'` → stream_id dolu. Discriminated union daha açık. | Story tipleri çoğalırsa tetikle — koşullu | Story refactor sprint'i |
