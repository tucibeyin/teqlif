# i18n Runtime Decoupling Planı ve Görev Takibi

Bu döküman, backend çalışma zamanının (runtime) fiziksel ARB dosyalarından (`documents/language/app_{lang}.arb`) tamamen bağımsız hale getirilmesi (decoupling) sürecini, mimari planı ve canlı görev takip listesini içerir.

---

## 🎯 Mimari Hedef ve Gerekçe
Eski mimaride `backend/app/utils/i18n.py` içindeki `_get_t(lang)` fonksiyonu, her çağrıldığında fiziksel `.arb` dosyalarının disk mtime zaman damgasını kontrol edip dosyayı okumaktaydı. 

Yeni OTA çeviri mimarimizde ARB dosyaları artık sadece geliştiriciler arası **Sözleşme (Contract)** ve veritabanını (`translations` tablosu) besleyen **Tek Hakikat Kaynağı (Single Source of Truth - Seed Source)** rolünü üstlenmiştir.

Canlı sunucuda çalışan API, worker, e-posta ve bildirim servisleri diskteki dosyalara asla dokunmamalı; çevirileri doğrudan **Bellek Ön Belleği (In-Memory Cache)**, **Redis (`i18n:{lang}`)** veya **Veritabanı (`translations` tablosu)** üzerinden okumalıdır.

```mermaid
flowchart TD
    subdiagram [Geliştirme / Deployment Aşaması]
    ARB[documents/language/app_*.arb] -->|sync_translations.py| DB[(PostgreSQL translations tablosu)]
    DB -->|Cache Invalidation & Seed| REDIS[(Redis i18n:lang)]
    
    subdiagram_run [Runtime - Backend Servisleri]
    REQ[_get_tlang Çağrısı] --> MEM{In-Memory TTL Cache<br/>Geçerli mi?}
    MEM -->|Evet| RET[Çeviri Dict Döner - 0 I/O]
    MEM -->|Hayır / Süre Doldu| RCK{Redis Cache<br/>i18n:lang Var mı?}
    RCK -->|Evet| UPD_MEM[In-Memory Cache Güncelle]
    RCK -->|Hayır| DB_Q[Veritabanından Sorgula]
    DB_Q --> UPD_REDIS[Redis ve In-Memory Güncelle]
    UPD_MEM --> RET
    UPD_REDIS --> RET
```

---

## 🛠️ Uygulama Planı

### 1. `app/utils/i18n.py` Servisinin Refactor Edilmesi
- Disk okuma (`_arb_path`, dosya açma, `_ARB_MTIME` kontrolü) kodları tamamen kaldırılacak.
- Bellekte 5 dakika TTL süreli `_MEMORY_CACHE` yapısı kurulacak (böylece sunucu yeniden başlatılmadan `sync_translations.py` sonrası güncel çeviriler otomatik alınır).
- Senkron çalışan `_get_t(lang)` fonksiyonu, önce belleğe bakacak; yoksa veya süresi dolmuşsa senkron Redis/DB okuması ile belleği tazeleyip sıfır disk bağımlılığıyla çalışacak.
- Asenkron bağlamlar (FastAPI startup) için `async def preload_i18n_cache()` yardımcı fonksiyonu eklenecek.

### 2. `main.py` Açılış Rutinine Pre-loading Eklenmesi
- FastAPI uygulaması ayağa kalkarken (`lifespan` veya startup) `preload_i18n_cache()` çağrılacak.
- Böylece API ilk açıldığı anda tüm diller (`tr`, `en`, `ar`, `ru`) Redis/DB'den belleğe alınacak ve ilk isteğin gecikmesi (cold-start latency) sıfırlanacak.

### 3. Geriye Dönük Uyumluluk ve Doğrulama
- Mevcut tüm senkron kullanım noktaları (`email.py`, `worker.py`, routers) hiçbir kod değişikliğine gerek kalmadan aynı imza (`_get_t(lang)`) ile çalışmaya devam edecek.
- Bir test betiği ile disk dosyaları olmadan da `_get_t()` servisinin doğru çevirileri döndürdüğü doğrulanacak.

---

## 📋 Görev Takip Listesi (Tasks)

- `[x]` **Task 1: `app/utils/i18n.py` içindeki disk bağımlılığının kaldırılması ve Redis/DB destekli TTL ön bellek yapısının kodlanması**
  - Dosya yolu hesaplama ve `open(...)` mantığının temizlenmesi.
  - Senkron Redis okuması (`redis.Redis.from_url`) ve senkron DB fallback mantığının eklenmesi.
  - Asenkron ön yükleme (`preload_i18n_cache`) fonksiyonunun eklenmesi.

- `[x]` **Task 2: `backend/main.py` başlangıç rutinine ön yükleyicinin (pre-loader) entegre edilmesi**
  - Uygulama başlarken 4 dilin de belleğe alınarak hazır hale getirilmesi.

- `[x]` **Task 3: Doğrulama ve Test**
  - `_get_t("tr")`, `_get_t("en")` vb. çağrıların test betiği ile kontrol edilmesi.
  - `sync_translations.py` ve e-posta şablonlarının sorunsuz çalıştığının doğrulanması.
