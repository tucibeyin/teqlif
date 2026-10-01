# Teqlif Scale V2.0 — Sistem Haritası (DRAFT)

> **Sürüm:** V2.0 (DRAFT)  
> **Durum:** Kurulum / Test Aşamasında  
> **Güncelleme:** 2026-09-29  
> **Kaynak dizin:** `deploy/scale/V2.0/`

---

## İçindekiler

1. [Genel Bakış ve Mimari Mantık](#1-genel-bakış-ve-mimari-mantık)
2. [Donanım Haritası](#2-donanım-haritası)
3. [Communication Architecture](#3-communication-architecture)
4. [Integration Architecture](#4-integration-architecture)
5. [Technology Architecture](#5-technology-architecture)
6. [Dependency Architecture](#6-dependency-architecture)
7. [Topology Architecture](#7-topology-architecture)
8. [Configuration Architecture](#8-configuration-architecture)
9. [Servis Dağılım Matrisi](#9-servis-dağılım-matrisi)
10. [Port Haritası](#10-port-haritası)
11. [DNS & Cloudflare Yapısı](#11-dns--cloudflare-yapısı)
12. [Güvenlik Mimarisi](#12-güvenlik-mimarisi)
13. [Monitoring & Observability](#13-monitoring--observability)
14. [Kritik Yapılandırma Notları](#14-kritik-yapılandırma-notları)
15. [Operasyon Rehberi](#15-operasyon-rehberi)
16. [TTL, Veri Yaşam Döngüsü ve Zamanlama Haritası](#16-ttl-veri-yaşam-döngüsü-ve-zamanlama-haritası)
17. [Gelecek (V2.1) Aday Konular](#17-gelecek-v21-aday-konular)

---

## 1. Genel Bakış ve Mimari Mantık
*(Kurulumlar tamamlandıktan sonra doldurulacak: V2.0 ile gelen Gateway bypass (Presigned S3), CQRS ayrışması, Guardian Agent metrik yapısı, Active-Active MinIO Site Replication ve Keepalived destekli Active-Passive Core veritabanı cluster'ının genel özeti.)*

## 2. Donanım Haritası
*(Kurulumlar tamamlandıktan sonra doldurulacak: 11 Node'luk yeni cluster topolojisi, VPS türleri, CPU/RAM ve atanmış roller tablosu.)*

## 3. Communication Architecture
*(Kurulumlar tamamlandıktan sonra doldurulacak: Yeni WireGuard (wg0) Mesh ağı yapısı, Floating VIP yönlendirmeleri, Node 9 Quorum Ping hakemliği ve ağ içi iletişim kuralları.)*

## 4. Integration Architecture
*(Kurulumlar tamamlandıktan sonra doldurulacak: Dış sistemlerle (Firebase, APNS, Sentry, Cloudflare, Telegram Alertmanager vb.) iletişim ve entegrasyon şeması.)*

## 5. Technology Architecture
*(Kurulumlar tamamlandıktan sonra doldurulacak: Kullanılan tüm core yazılımların listesi — FastAPI, PostgreSQL 17, Redis, LiveKit, MinIO, ClickHouse, Prometheus/Loki vb.)*

## 6. Dependency Architecture
*(Kurulumlar tamamlandıktan sonra doldurulacak: Sistemde bir sunucu yeniden başlatıldığında, boot sırası (Örn: Önce WG -> Sonra DB -> Sonra App) ve bağımlılık haritası.)*

## 7. Topology Architecture
*(Kurulumlar tamamlandıktan sonra doldurulacak: Gateway, Core, Storage, Stream, AI Proxy, Monitor ve Staging node'larının ağ üzerindeki konumları ve izole edilmiş yetki sınırları.)*

## 8. Configuration Architecture
*(Kurulumlar tamamlandıktan sonra doldurulacak: `/etc/teqlif/node.conf` mantığı, çevresel değişkenlerin (`.env.production`) nasıl yönetildiği ve dağıtıldığı.)*

## 9. Servis Dağılım Matrisi
*(Kurulumlar tamamlandıktan sonra doldurulacak: Hangi sunucuda hangi Systemd servislerinin aktif çalıştığını gösteren ana tablo.)*

## 10. Port Haritası
*(Kurulumlar tamamlandıktan sonra doldurulacak: Node bazlı UFW kuralları, dahili WG portları (TCP/UDP) ve Cloudflare'e açılan dış portlar.)*

## 11. DNS & Cloudflare Yapısı
*(Kurulumlar tamamlandıktan sonra doldurulacak: `api.teqlif.com` (Proxied), `uploads.teqlif.com` (DNS Only), Staging ve Media CDN domainlerinin kayıt şeması.)*

## 12. Güvenlik Mimarisi
*(Kurulumlar tamamlandıktan sonra doldurulacak: fail2ban kısıtları, SSH anahtar yapısı, Journald (300M) limitleri ve Sudoers/NOPASSWD izin kuralları.)*

## 13. Monitoring & Observability
*(Kurulumlar tamamlandıktan sonra doldurulacak: Node 9 üzerindeki Prometheus hedefleri, Promtail Loki log akış yapısı ve ClickHouse Analytics analizi.)*

## 14. Kritik Yapılandırma Notları
*(Kurulumlar tamamlandıktan sonra doldurulacak: V2.0 sistemine özel "Gotcha"lar, Edge-agent failover toleransları ve Redis NX lock fallback kural setleri.)*

## 15. Operasyon Rehberi
*(Kurulumlar tamamlandıktan sonra doldurulacak: `teqlif-restart.sh`, `teqlif-refresh.sh` betiklerinin kullanımı, Split-brain riskinde (Node 6 izole kalırsa) manuel recovery adımları.)*

## 16. TTL, Veri Yaşam Döngüsü ve Zamanlama Haritası
*(Kurulumlar tamamlandıktan sonra doldurulacak: ARQ task cron takvimleri, PostgreSQL tablo silme/arşivleme TTL'leri ve Guardian Edge Metrics taze kalma (12s) süreleri.)*

## 17. Gelecek (V2.1) Aday Konular
*(Kurulumlar tamamlandıktan sonra doldurulacak: İlerleyen aylarda altyapıya kazandırılmak istenen teknik iyileştirmeler ve notlar.)*
