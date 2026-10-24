# Teqlif V2.1 — Ekonomi & Ölçeklenebilirlik Raporu

> Tarih: Ekim 2025 | Para birimi: TRY | Altyapı: V2.1 (7 node)

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

### Darboğaz Haritası

Sistem üç ayrı noktada sınıra ulaşır — farklı kullanıcı kütlelerinde:

```
DARBOĞAZ 1 — LiveKit (node3 + node4)           ← İLK KIRILIR
─────────────────────────────────────────────────────────────
Her node: 6vCPU, 12GB RAM, 2Gbps
720p stream başına: ~1,5-2 Mbps
Eş zamanlı max stream: ~200-250
Eş zamanlı izleyici: ~10.000 (200 stream × 50)
Tetiklenme: MAU ~40.000-60.000

DARBOĞAZ 2 — node1 CPU/RAM                     ← İKİNCİ
─────────────────────────────────────────────────────────────
6c/12t, 32GB RAM
13 uvicorn worker (2×CPU+1)
Redis 4GB → 8GB'a çekilebilir (RAM içinde)
Cloudflare statik trafiğin %65-70'ini absorbe eder
Eş zamanlı API: ~4.000-6.000
Tetiklenme: MAU ~80.000-100.000

DARBOĞAZ 3 — node1 Disk                        ← EN SON
─────────────────────────────────────────────────────────────
~920GB kullanılabilir (2×512GB RAID)
100K kullanıcıda %44 dolu (~405GB)
60 günlük DM medya arşivleme büyümeyi yavaşlatır
Tetiklenme: ~200.000 kayıtlı kullanıcı
```

---

### Son Damla Senaryo A — LiveKit Darboğazı

| Metrik | Değer |
|--------|-------|
| MAU | 50.000 |
| Kayıtlı | 120.000 |
| PRO abone (%7) | 3.500 |
| teqlik alıcı/ay | 7.500 × 1,3 |
| Aylık gelir | ₺1.989.255 |
| Aylık gider | ₺5.034 |
| **Net/ay** | **₺1.984.221** |
| **Net/yıl** | **₺23.810.652** |
| Kâr marjı | %99,7 |
| Çözüm | 2 ek LiveKit VPS (~₺1.500/ay) |

---

### Son Damla Senaryo B — node1 CPU/RAM Darboğazı

Config optimizasyonları (kod değişikliği yok):
- Redis maxmemory: 4GB → 8GB
- PgBouncer pool büyütüldü
- Cloudflare cache TTL agresif

| Metrik | Değer |
|--------|-------|
| MAU | 90.000 |
| Kayıtlı | 220.000 |
| PRO abone (%8) | 7.200 |
| teqlik alıcı/ay | 15.300 × 1,5 |
| Aylık gelir | ₺4.604.301 |
| Aylık gider | ₺8.034 (ek LiveKit dahil) |
| **Net/ay** | **₺4.596.267** |
| **Net/yıl** | **₺55.155.204** |
| Kâr marjı | %99,8 |
| Çözüm | node1 upgrade veya read-replica (~₺4.000/ay) |

---

### Son Damla Senaryo C — Disk Darboğazı (Gerçek Son Damla)

| Metrik | Değer |
|--------|-------|
| MAU | 130.000 |
| Kayıtlı | 200.000 |
| PRO abone (%8) | 10.400 |
| teqlik alıcı/ay | 23.400 × 1,6 |
| Aylık gelir | ₺7.405.322 |
| Aylık gider | ₺8.034 |
| **Net/ay** | **₺7.397.288** |
| **Net/yıl** | **₺88.767.456** |
| Kâr marjı | %99,9 |
| Çözüm | MinIO external storage (~₺500-2.000/ay) |

---

### Son Damla Özet Tablosu

| | Darboğaz 1 | Darboğaz 2 | Darboğaz 3 |
|-|------------|------------|------------|
| **MAU** | 50.000 | 90.000 | 130.000 |
| **PRO abone** | 3.500 | 7.200 | 10.400 |
| **teqlik satışı/ay** | 9.750 | 22.950 | 37.440 |
| **Aylık gelir** | ₺1.989.255 | ₺4.604.301 | ₺7.405.322 |
| **Aylık gider** | ₺5.034 | ₺8.034 | ₺8.034 |
| **Net/ay** | ₺1.984.221 | ₺4.596.267 | ₺7.397.288 |
| **Net/yıl** | ₺23,8M | ₺55,2M | ₺88,8M |
| **Altyapı/gelir** | %0,25 | %0,17 | %0,11 |
| **Çözüm maliyeti** | ₺1.500/ay | ₺4.000/ay | ₺2.000/ay |

---

## 6. Temel Bulgular

1. **Altyapı maliyeti hiçbir senaryoda gelirin %1'ini geçmiyor.**
   Sektör ortalaması %5-15 iken bu oran istisnai düzeyde düşüktür.

2. **Her darboğazın çözüm maliyeti o ayın kârının binde birinden az.**
   Ölçekleme neredeyse sıfır marjinal maliyetle gerçekleşir.

3. **teqlik geliri PRO gelirinin 8-9 katı.**
   Platform aktivitesi monetizasyonun gerçek motorudur.
   Kullanıcı aktivitesi = doğrudan gelir.

4. **İlk yatırım LiveKit'e yapılmalı.**
   Sistemin en erken kilit noktası node3+node4'tür.
   2 ek LiveKit VPS (~₺1.500/ay) ile Senaryo A → B'ye geçilir.

5. **Mevcut donanımla teorik maksimum: ₺88,8M net/yıl.**
   Hiçbir kod değişikliği olmadan, yalnızca config + 2 ek VPS.

6. **Zarar penceresi: Ay 1-4, maksimum ~₺13.000.**
   Harici finansman gerekmez, kişisel karşılanabilir düzeyde.

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
