# Teqlif Scale Planı — V1.0

**Durum:** Geliştirme aşaması, henüz canlı trafik yok.  
**Sunucu:** OVH VPS — 6 vCore / 12 GB RAM / 100 GB NVMe  
**Tarih:** 2026-09-06

---

## Baseline Benchmark Sonuçları

Testler Gemini tarafından planlandı; trafiksiz, rölanti durumdaki sunucunun taban çizgisini ölçmek amacıyla yapıldı. Ölçülen değerler darboğaz noktalarını belirlemek için referans alınacak — gerçek trafik geldiğinde bu testler tekrar çalıştırılacak.

### 1. Disk I/O (fio) — 4K Rastgele Okuma/Yazma, 1 GB

| Metrik  | Değer             |
|---------|-------------------|
| Okuma   | 119 MB/s / 30.5k IOPS |
| Yazma   | 39.8 MB/s / 10.2k IOPS |
| İş derinliği | iodepth=64 |

**Yorum:** PostgreSQL ve MinIO için yeterli. Darboğaz değil.

---

### 2. FastAPI / Uvicorn HTTP Dayanıklılık (wrk)

**Komut:** `wrk -t12 -c400 -d30s http://127.0.0.1:8000/api/health`

| Metrik | Değer |
|--------|-------|
| Toplam istek | 54,148 |
| Başarılı (2xx) | 307 |
| Başarısız | 53,841 (%99.4) |
| Throughput | 1,799 req/s (toplam) |
| Ortalama gecikme | 224 ms |

**Not:** Yüksek hata oranı uygulamanın yetersizliğinden değil, anti-bot middleware'inden kaynaklanıyor. Tüm 400 bağlantı tek IP (127.0.0.1) üzerinden geliyor; 300 istek/dk limiti aşılınca IP 10 dk bloke ediliyor. Ayrıca `_BYPASS_PATHS` listesinde `/health` var ama endpoint `/api/health` — middleware atlatılamıyor. Gerçek trafikte farklı IP'ler geldiği için bu durum oluşmaz.

**Yeniden test önerisi:** Gerçek trafik başladıktan sonra nginx üzerinden test edilmeli (`127.0.0.1:80`) ve `_BYPASS_PATHS`'e `/api/health` eklenmeli.

---

### 3. PostgreSQL Stres Testi (pgbench)

**Komut:** `pgbench -c 100 -j 4 -T 60 pgbench_test` (scale 50, ~750 MB)

| Metrik | Değer |
|--------|-------|
| Bağlantı limiti aşıldı | 72. client'ta |
| Hata | `FATAL: sorry, too many clients already` |
| TPS | Ölçülemedi (bağlantı limiti nedeniyle) |

**Kök neden:** PostgreSQL `max_connections ≈ 100`. Uygulama (prod + staging) yaklaşık 28-30 connection kullanıyor; pgbench 72. client'ta dolduruyor.

**Not:** Async uygulama aynı anda pool'un tamamını kullanmaz (bekleme sırasında connection serbest kalır). Mevcut `pool_size=20, max_overflow=10` gerçek trafik için yeterli.

---

## Sonraki Adımlar (Trafik Gelince)

- [ ] Testleri gerçek trafik altında tekrar çalıştır (canlı kullanıcılarla eş zamanlı)
- [ ] pgbench TPS değerini ölç (bu sefer ayrı test DB, ayrı terminal)
- [ ] Mikroservis dağılımını bu rakamlara göre planla
- [ ] `_BYPASS_PATHS`'e `/api/health` ekle (monitoring için)
- [ ] PostgreSQL `max_connections` ve PgBouncer ihtiyacını değerlendir
