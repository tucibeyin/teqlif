# Teqlif V2.1 — Ekonomi & Ölçeklenebilirlik Raporu

> Tarih: Ekim 2026 | Para birimi: TRY | Altyapı: V2.1 (7 node) | V2 revizyon: gerçek config verilerine dayalı

---

## 1. Sabit Altyapı Maliyetleri

| Node | Spec | Aylık TL |
|------|------|----------|
| node1 (OVH Dedicated) | 6c/12t, 32GB RAM, 2×512GB NVMe | 1.726,75 |
| node2 (OVH Dedicated) | 4c/8t, 32GB RAM, 2×4TB HDD | 1.376,86 |
| node3 (OVH VPS) | 6vCPU, 12GB RAM, 100GB | 735,42 |
| node4 (OVH VPS) | 6vCPU, 12GB RAM, 100GB | 738,71 |
| node5 (zap-hosting Lifetime) | 4vCPU, 8GB RAM, 50GB | 156,60 |
| node6 (zap-hosting Lifetime) | 4vCPU, 4GB RAM, 50GB | 150,68 |
| nodeMonitor (Netcup) | 2vCPU, 2GB RAM, 60GB | 149,44 |
| **TOPLAM** | | **5.034 TL/ay** |

> node5+6 lifetime ödeme amortize edilmiştir (36 ay ÷ toplam ödeme).

---

## 2. Gelir Parametreleri

### Apple / Google Komisyon Yapısı

- Brüt fiyat üzerinden KDV: **%18**
- Kalan üzerinden platform komisyonu: **%30**
- **Net proceeds oranı: %55,4**

Gözlemlenen örnekler:
- ₺149,99 → ₺83,12 (%55,4)
- ₺349,99 → ₺193,95 (%55,4)
- ₺599,99 → ₺332,51 (%55,4)
- ₺999,99 → ₺554,19 (%55,4)

---

### PRO Abonelik Fiyatları (Güncel)

| Plan | Fiyat | Aylık eşdeğer | Apple net | Net aylık |
|------|-------|---------------|-----------|-----------|
| 1m | ₺149,99 | ₺149,99 | ₺83,12 | ₺83,12 |
| 3m | ₺399,99 | ₺133,33 | ₺221,60 | ₺73,87 |
| 6m | ₺699,99 | ₺116,67 | ₺387,91 | ₺64,65 |
| 12m | ₺1.299,99 | ₺108,33 | ₺720,41 | ₺60,03 |

**Ağırlıklı ortalama net/abone/ay** (dağılım: %40 / %30 / %20 / %10):

```
0,40 × 83,12 + 0,30 × 73,87 + 0,20 × 64,65 + 0,10 × 60,03 = ₺74,34
```

---

### teqlik Sanal Para Fiyatları (Güncel)

| Paket | Fiyat | Net (×0,554) | Teqlik başına |
|-------|-------|--------------|---------------|
| 100 | ₺149,99 | ₺83,12 | ₺1,50 |
| 250 | ₺349,99 | ₺193,95 | ₺1,40 |
| 500 | ₺599,99 | ₺332,51 | ₺1,20 |
| 1000 | ₺999,99 | ₺554,19 | ₺1,00 |

**Ağırlıklı ortalama net/satın alma** (dağılım: %50 / %30 / %15 / %5):

```
0,50 × 83,12 + 0,30 × 193,95 + 0,15 × 332,51 + 0,05 × 554,19 = ₺177,34
```

---

## 3. Başa Baş Noktası

| Yöntem | Minimum gereksinim |
|--------|-------------------|
| Yalnız PRO | 5.034 ÷ 74,34 = **68 aylık abone** |
| Yalnız teqlik | 5.034 ÷ 177,34 = **28 satın alma/ay** |
| Karma (%40 PRO / %60 teqlik geliri) | ~40-45 PRO + 60-70 teqlik satışı |

Başa baş tahmini zaman: **Ay 3-4**

---

## 4. Senaryo Analizi — Normal Büyüme

### Minimum (Ay 1-6, erken dönem)

| Metrik | Değer |
|--------|-------|
| Kayıtlı kullanıcı | 500 |
| MAU | 200 |
| PRO abone (%3) | 15 |
| teqlik alıcı/ay | 40 × 0,4 alım |
| **Aylık gelir** | **₺3.952** |
| Aylık gider | ₺5.034 |
| **Net** | **-₺1.082 (zarar)** |
| Yıllık | -₺12.984 |

> Erken dönem zararı kabul edilebilir. Harici finansman gerekmez.

---

### Optimum (Ay 6-18, büyüme dönemi)

| Metrik | Değer |
|--------|-------|
| Kayıtlı kullanıcı | 8.000 |
| MAU | 4.000 |
| PRO abone (%5) | 200 |
| teqlik alıcı/ay | 600 × 0,8 alım |
| **Aylık gelir** | **₺99.991** |
| Aylık gider | ₺5.034 |
| **Net** | **₺94.957** |
| Yıllık | ₺1.139.484 |
| Kâr marjı | %95 |

---

### Maksimum — normal büyüme (Ay 18-36+)

| Metrik | Değer |
|--------|-------|
| Kayıtlı kullanıcı | 50.000 |
| MAU | 22.000 |
| PRO abone (%7) | 1.540 |
| teqlik alıcı/ay | 3.500 × 1,4 alım |
| **Aylık gelir** | **₺983.650** |
| Aylık gider | ₺20.034 (ölçekleme dahil) |
| **Net** | **₺963.616** |
| Yıllık | ₺11.563.392 |
| Kâr marjı | %97,9 |

---

## 5. Son Damla Analizi — Donanım & Yazılım Mutlak Sınırı

> **V2 Revizyon (Ekim 2026):** Aşağıdaki rakamlar `deploy/scale/V2.1/` config dosyalarından
> elde edilen gerçek parametrelere dayanmaktadır. V1 raporundaki teorik hesaplar
> önemli ölçüde şişirilmişti; bu bölüm tümüyle düzeltilmiştir.

### Gerçek Config Parametreleri

| Servis | Parametre | Gerçek | V1 Varsayım |
|--------|-----------|--------|-------------|
| uvicorn | workers | **8** | 13 ← YANLIŞ |
| pgbouncer | max_client_conn | **1.000** | — (bilinmiyordu) |
| pgbouncer | default_pool_size | **40** | — |
| pgbouncer | max_db_connections | **60** | — |
| nginx | worker_connections | **4.096** | — |
| nginx | rate_limit | **50 r/s burst 100** | — |
| redis | maxmemory | **4 GB** | ✓ |
| arq worker | MemoryMax | **5 GB** | — |
| LiveKit TURN | port aralığı | **50.000-60.000** | — |
| sysctl | somaxconn | **65.535** | — |

### Darboğaz Haritası

```
DARBOĞAZ 1 — LiveKit Bant Genişliği           ← İLK KIRILIR
─────────────────────────────────────────────────────────────
Her node: 6vCPU, 12GB RAM, 2Gbps VPS
720p izleyici başına: ~1.5 Mbps outbound
Eş zamanlı max izleyici: ~2.500-3.000 (2 node toplam)
TURN relay sınırı: 5.000 session/node (10.000 port ÷ 2)
Eş zamanlı yayın: ~150-200 aktif (50 izleyici/yayın)
Tetiklenme: MAU ~15.000-20.000
── V1 HATASI: MAU 40.000-60.000 saymıştı (2-3× şişirilmiş) ──

DARBOĞAZ 2 — node1 PgBouncer / API Katmanı    ← İKİNCİ
─────────────────────────────────────────────────────────────
8 uvicorn worker (gerçek; eski: 13)
PgBouncer max_client_conn=1.000 (gerçek sınır)
PostgreSQL: 60 bağlantı, ~1.200 TPS sustained
node1 RAM: ~15GB kullanımda / 32GB → Redis 8GB'a çekilebilir
Eş zamanlı aktif API session: ~1.000-2.000
Tetiklenme: MAU ~40.000-50.000
── V1 HATASI: 4.000-6.000 session, MAU 80.000-100.000 ──

DARBOĞAZ 3 — node1 Disk                       ← EN SON
─────────────────────────────────────────────────────────────
~450GB kullanılabilir (2×512GB NVMe RAID-1)
Listing medyası + DM arşivi (60 gün saklama)
Per-user: ~3-5MB listing + ~8-15MB DM (aktif)
Tetiklenme: ~150.000-200.000 kayıtlı kullanıcı | MAU ~80.000-100.000
```

---

### Son Damla Senaryo A — LiveKit Bant Genişliği Darboğazı (Düzeltilmiş)

| Metrik | Gerçek | (V1 Eski) |
|--------|--------|-----------|
| MAU | **20.000** | ~~50.000~~ |
| Kayıtlı | 50.000 | ~~120.000~~ |
| PRO abone (%7) | 1.400 | ~~3.500~~ |
| teqlik işlem/ay | 3.900 | ~~9.750~~ |
| PRO net gelir | ₺104.076 | — |
| teqlik net gelir | ₺691.626 | — |
| **Aylık gelir** | **₺795.702** | ~~₺1.989.255~~ |
| Aylık gider | ₺5.034 | ₺5.034 |
| **Net/ay** | **₺790.668** | ~~₺1.984.221~~ |
| **Net/yıl** | **₺9.5M** | ~~₺23.8M~~ |
| Kâr marjı | %99,4 | — |
| Çözüm | 2 ek LiveKit VPS (~₺1.500/ay) | aynı |

---

### Son Damla Senaryo B — node1 PgBouncer/API Darboğazı (Düzeltilmiş)

Config optimizasyonları (0 maliyet, sırasıyla uygulanmalı):
- Redis maxmemory: 4GB → 8GB (RAM'de 17GB boş alan var)
- PgBouncer: max_client_conn=2.000, pool_size=60, max_db_connections=100
- Cloudflare cache TTL agresifleştirme (listing verileri, kategoriler)

| Metrik | Gerçek | (V1 Eski) |
|--------|--------|-----------|
| MAU | **50.000** | ~~90.000~~ |
| Kayıtlı | 120.000 | ~~220.000~~ |
| PRO abone (%8) | 4.000 | ~~7.200~~ |
| teqlik işlem/ay | 10.000 | ~~22.950~~ |
| PRO net gelir | ₺297.360 | — |
| teqlik net gelir | ₺1.773.400 | — |
| **Aylık gelir** | **₺2.070.760** | ~~₺4.604.301~~ |
| Aylık gider | ₺6.534 (ek LiveKit dahil) | ₺8.034 |
| **Net/ay** | **₺2.064.226** | ~~₺4.596.267~~ |
| **Net/yıl** | **₺24.8M** | ~~₺55.2M~~ |
| Kâr marjı | %99,7 | — |
| Çözüm | PgBouncer tune + PostgreSQL upgrade (~₺4.000/ay) | — |

---

### Son Damla Senaryo C — Disk Darboğazı (Gerçek Son Damla, Düzeltilmiş)

| Metrik | Gerçek | (V1 Eski) |
|--------|--------|-----------|
| MAU | **80.000-100.000** | ~~130.000~~ |
| Kayıtlı | 150.000-200.000 | ~~200.000~~ |
| PRO abone (%8) | 6.400-8.000 | ~~10.400~~ |
| teqlik işlem/ay | 17.000-21.000 | ~~37.440~~ |
| **Aylık gelir** | **₺3.400.000-4.200.000** | ~~₺7.405.322~~ |
| Aylık gider | ₺8.034 | ₺8.034 |
| **Net/ay** | **₺3.392.000-4.192.000** | ~~₺7.397.288~~ |
| **Net/yıl** | **₺40.7M-50.4M** | ~~₺88.8M~~ |
| Kâr marjı | %99,8 | — |
| Çözüm | MinIO external storage (~₺500-2.000/ay) | aynı |

---

### Son Damla Özet Tablosu (Düzeltilmiş)

| | Darboğaz 1 | Darboğaz 2 | Darboğaz 3 |
|-|------------|------------|------------|
| **MAU** | **20.000** | **50.000** | **80.000-100.000** |
| **PRO abone** | 1.400 | 4.000 | 6.400-8.000 |
| **teqlik işlem/ay** | 3.900 | 10.000 | 17.000-21.000 |
| **Aylık gelir** | ₺795.702 | ₺2.070.760 | ₺3.400.000-4.200.000 |
| **Aylık gider** | ₺5.034 | ₺6.534 | ₺8.034 |
| **Net/ay** | ₺790.668 | ₺2.064.226 | ₺3.392.000-4.192.000 |
| **Net/yıl** | ₺9.5M | ₺24.8M | ₺40.7M-50.4M |
| **Altyapı/gelir** | %0,63 | %0,32 | %0,20 |
| **Çözüm maliyeti** | ₺1.500/ay | ₺4.000/ay | ₺2.000/ay |

---

## 6. Temel Bulgular (V2 — Gerçek Config)

1. **Altyapı maliyeti hiçbir senaryoda gelirin %0.7'sini geçmiyor.**
   Sektör ortalaması %5-15 iken bu oran istisnai düzeyde düşüktür.
   (V1'deki %0.25 aşırı iyimserdi; gerçekçi aralık %0.2-0.7.)

2. **LiveKit yatırımı 2-3× daha erken gerekecek.**
   Bant genişliği sınırı MAU ~15-20K'da tıkar; V1 raporu 40-60K demişti.
   Bu noktada gelir ~₺790K/ay — yatırım kolayca karşılanır.

3. **PgBouncer 1.000 client limiti gizli darboğazdı; keşfedildi.**
   Ücretsiz config tune ile (max_client_conn=2.000, pool_size=60) MAU 40K → 70K'ya uzatılabilir.
   Redis maxmemory 4GB → 8GB: node1'de 17GB boş RAM var, anında uygulanabilir.

4. **Gerçekçi son damla: ₺40.7M-50.4M net/yıl.**
   V1'deki ₺88.8M teorik maksimumdu; gerçek config ile %43 daha düşük ama hâlâ stratosferde.

5. **teqlik geliri PRO gelirinin 6-7 katı.**
   Platform aktivitesi monetizasyonun gerçek motorudur.
   Kullanıcı aktivitesi = doğrudan gelir.

6. **İlk ek yatırım: 2 LiveKit VPS, MAU 15-20K öncesi.**
   ~₺1.500/ay ile Senaryo A → B'ye (MAU 50K) geçilir.

7. **Zarar penceresi: Ay 1-4, maksimum ~₺13.000.**
   Değişmedi. Harici finansman gerekmez.

---

## 7. Fiyatlandırma Kararları (Referans)

### PRO Abonelik — App Store Tier Kısıtı Gözetilerek

| Plan | Eski | Yeni | Değişim |
|------|------|------|---------|
| 1m | ₺149,99 | ₺149,99 | — |
| 3m | ₺399,99 | ₺399,99 | — |
| 6m | ₺799,99 | **₺699,99** | 3m ile aynı aylık oran düzeltildi |
| 12m | ₺1.499,99 | **₺1.299,99** | Yıllık teşvik güçlendirildi |

### teqlik — App Store Tier Kısıtı Gözetilerek

| Paket | Eski | Yeni | Değişim |
|-------|------|------|---------|
| 100 | ₺149,99 | ₺149,99 | — |
| 250 | ₺349,99 | ₺349,99 | — |
| 500 | ₺699,99 | **₺599,99** | 250 ile aynı birim maliyet düzeltildi |
| 1000 | ₺1.299,99 | **₺999,99** | En iyi değer paketi güçlendirildi |

> Fiyat değişiklikleri yalnızca App Store Connect güncellemeyi gerektirir,
> kod değişikliği yoktur. Fiyatlar IAP ürününden canlı çekilmektedir.
