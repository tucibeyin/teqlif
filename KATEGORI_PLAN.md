# Teqlif — Kategori & İlan Verisi Genişletme Planı

Son güncelleme: 2026-07-23

---

## Genel Strateji

- 8 ana kategori korunur, alt kategorilerle genişletilir
- Her alt kategori için: alanlar, kondisyonlar, marka/model kapsama
- Title serbest metin; diğer tüm alanlar dropdown
- Marka → Model zincirleme filtreli dropdown
- Kondisyon seti alt kategoriye göre dinamik
- Renk alanı şimdilik yalnızca Apple / iPhone için

---

## Durum Göstergesi

✅ Tamamlandı  |  🔄 Üzerinde çalışılıyor  |  ⏳ Henüz başlanmadı

---

## 1. ELEKTRONİK ✅

### Alt Kategoriler

| #  | Ad                        | Slug                | Durum |
|----|---------------------------|---------------------|-------|
| 01 | Cep Telefonu              | cep-telefonu        | 🔄    |
| 02 | Akıllı Saat & Bileklik    | akilli-saat         | ⏳    |
| 03 | Bilgisayar & Laptop       | bilgisayar-laptop   | ⏳    |
| 04 | Tablet                    | tablet              | ⏳    |
| 05 | TV & Monitör              | tv-monitor          | ⏳    |
| 06 | Ses Sistemi & Kulaklık    | ses-sistemi         | ⏳    |
| 07 | Fotoğraf & Kamera         | fotograf-kamera     | ⏳    |
| 08 | Oyun Konsolu & Aksesuar   | oyun-konsolu        | ⏳    |
| 09 | Beyaz Eşya                | beyaz-esya          | ⏳    |
| 10 | Klima & Isıtma            | klima-isitma        | ⏳    |
| 11 | Diğer Elektronik          | diger-elektronik    | ⏳    |

---

### 1.01 — Cep Telefonu 🔄

**Alanlar:**

| Alan       | Tip            | Detay                                              |
|------------|----------------|----------------------------------------------------|
| Title      | Serbest metin  | Kullanıcı elle girer                               |
| Marka      | Dropdown       | —                                                  |
| Model      | Dropdown       | Markaya göre filtreli                              |
| Depolama   | Dropdown       | 64GB / 128GB / 256GB / 512GB / 1TB                |
| Renk       | Dropdown       | Yalnızca Apple seçildiğinde görünür (conditional) |
| Kondisyon  | Dropdown       | Aşağıya bak                                        |
| Lokasyon   | Mevcut sistem  | —                                                  |

**Kondisyonlar:**
- Sıfır (new)
- Az Kullanılmış (like_new)
- İkinci El (used)
- Hasarlı (damaged)
- Yenilenmiş (refurbished) ← Cep Telefonu'na özel

**Renk listesi (yalnızca Apple):**
Siyah · Beyaz · Mavi · Yeşil · Mor · Sarı · Pembe · Kırmızı · Gümüş · Altın · Gri

**Marka / Model:**
⏳ Araştırılacak — Türkiye pazarı öncelikli seed seti

---

### 1.02 — Akıllı Saat & Bileklik ✅

**Alanlar:**

| Alan       | Tip           | Detay                      |
|------------|---------------|----------------------------|
| Title      | Serbest metin | Kullanıcı elle girer       |
| Marka      | Dropdown      | —                          |
| Model      | Dropdown      | Markaya göre filtreli      |
| Kondisyon  | Dropdown      | Aşağıya bak                |
| Lokasyon   | Mevcut sistem | —                          |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı
(Yenilenmiş yok — pazarda segment küçük)

---

### 1.03 — Bilgisayar & Laptop ✅

**Alanlar:**

| Alan       | Tip           | Detay                                    |
|------------|---------------|------------------------------------------|
| Title      | Serbest metin | Kullanıcı elle girer                     |
| Marka      | Dropdown      | —                                        |
| Model      | Dropdown      | Markaya göre filtreli                    |
| RAM        | Dropdown      | 8 / 16 / 32 / 64GB                      |
| Depolama   | Dropdown      | 256GB / 512GB / 1TB / 2TB SSD           |
| Kondisyon  | Dropdown      | Aşağıya bak                              |
| Lokasyon   | Mevcut sistem | —                                        |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.04 — Tablet ✅

**Alanlar:**

| Alan       | Tip           | Detay                          |
|------------|---------------|--------------------------------|
| Title      | Serbest metin | Kullanıcı elle girer           |
| Marka      | Dropdown      | —                              |
| Model      | Dropdown      | Markaya göre filtreli          |
| RAM        | Dropdown      | 4 / 6 / 8 / 12 / 16GB        |
| Depolama   | Dropdown      | 64 / 128 / 256 / 512GB        |
| Kondisyon  | Dropdown      | Aşağıya bak                    |
| Lokasyon   | Mevcut sistem | —                              |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.05 — TV & Monitör ✅

**Alanlar:**

| Alan          | Tip           | Detay                              |
|---------------|---------------|------------------------------------|
| Title         | Serbest metin | Kullanıcı elle girer               |
| Marka         | Dropdown      | —                                  |
| Model         | Dropdown      | Markaya göre filtreli              |
| Ekran Boyutu  | Dropdown      | 32" / 40" / 43" / 50" / 55" / 65" / 75" / 85"+ |
| Çözünürlük    | Dropdown      | HD / Full HD / 4K / 8K            |
| Kondisyon     | Dropdown      | Aşağıya bak                        |
| Lokasyon      | Mevcut sistem | —                                  |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.06 — Ses Sistemi & Kulaklık ✅

**Alanlar:**

| Alan       | Tip           | Detay                  |
|------------|---------------|------------------------|
| Title      | Serbest metin | Kullanıcı elle girer   |
| Marka      | Dropdown      | —                      |
| Model      | Dropdown      | Markaya göre filtreli  |
| Kondisyon  | Dropdown      | Aşağıya bak            |
| Lokasyon   | Mevcut sistem | —                      |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.07 — Fotoğraf & Kamera ✅

**Alanlar:**

| Alan       | Tip           | Detay                                                        |
|------------|---------------|--------------------------------------------------------------|
| Title      | Serbest metin | Kullanıcı elle girer                                         |
| Marka      | Dropdown      | —                                                            |
| Model      | Dropdown      | Markaya göre filtreli                                        |
| Tip        | Dropdown      | DSLR / Aynasız / Aksiyon Kamera / Drone / Lens / Aksesuar  |
| Kondisyon  | Dropdown      | Aşağıya bak                                                  |
| Lokasyon   | Mevcut sistem | —                                                            |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.08 — Oyun Konsolu & Aksesuar ✅

**Alanlar:**

| Alan       | Tip           | Detay                                              |
|------------|---------------|----------------------------------------------------|
| Title      | Serbest metin | Kullanıcı elle girer                               |
| Marka      | Dropdown      | —                                                  |
| Model      | Dropdown      | Markaya göre filtreli                              |
| Tip        | Dropdown      | Konsol / Kol & Joystick / Oyun Kartuşu / Aksesuar |
| Depolama   | Dropdown      | 256GB / 512GB / 1TB / 2TB — yalnızca Tip=Konsol   |
| Kondisyon  | Dropdown      | Aşağıya bak                                        |
| Lokasyon   | Mevcut sistem | —                                                  |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.09 — Beyaz Eşya ✅

**Alanlar (bağımlılık sırasına göre):**

| Sıra | Alan       | Tip           | Bağımlı Olduğu | Detay                                                                |
|------|------------|---------------|-----------------|----------------------------------------------------------------------|
| 1    | Title      | Serbest metin | —               | Kullanıcı elle girer                                                 |
| 2    | Tip        | Dropdown      | —               | Buzdolabı / Çamaşır Makinesi / Bulaşık Makinesi / Fırın & Ocak / Mikrodalga / Derin Dondurucu / Diğer |
| 3    | Marka      | Dropdown      | Tip             | Tipe göre filtreli                                                   |
| 4    | Model      | Dropdown      | Marka           | Markaya göre filtreli                                                |
| 5    | Kapasite   | Dropdown      | Tip             | Tipe göre değişir (aşağıya bak)                                     |
| 6    | Kondisyon  | Dropdown      | —               | Aşağıya bak                                                          |
| 7    | Lokasyon   | Mevcut sistem | —               | —                                                                    |

**Kapasite — Tipe göre detaylı liste:**

| Tip               | Seçenekler                                           |
|-------------------|------------------------------------------------------|
| Buzdolabı         | 100-150L / 150-250L / 250-400L / 400L+              |
| Çamaşır Makinesi  | 5kg / 6kg / 7kg / 8kg / 9kg / 10kg+                |
| Bulaşık Makinesi  | 6 kişilik / 9 kişilik / 12 kişilik / 14 kişilik+   |
| Fırın & Ocak      | 45L / 60L / 70L / 90L+                             |
| Mikrodalga        | 17L / 20L / 23L / 25L / 30L+                       |
| Derin Dondurucu   | 100-200L / 200-300L / 300-500L / 500L+             |
| Diğer             | Küçük / Orta / Büyük                                |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.10 — Klima & Isıtma ✅

**Alanlar (bağımlılık sırasına göre):**

| Sıra | Alan            | Tip           | Bağımlı Olduğu | Detay                                                        |
|------|-----------------|---------------|-----------------|--------------------------------------------------------------|
| 1    | Title           | Serbest metin | —               | Kullanıcı elle girer                                         |
| 2    | Tip             | Dropdown      | —               | Klima / Isıtıcı / Kombi / Şofben / Radyatör / Diğer        |
| 3    | Marka           | Dropdown      | Tip             | Tipe göre filtreli                                           |
| 4    | Model           | Dropdown      | Marka           | Markaya göre filtreli                                        |
| 5    | BTU / Kapasite  | Dropdown      | Tip             | Yalnızca Tip=Klima → 9.000 / 12.000 / 18.000 / 24.000 BTU+ |
| 6    | Kondisyon       | Dropdown      | —               | Aşağıya bak                                                  |
| 7    | Lokasyon        | Mevcut sistem | —               | —                                                            |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

### 1.11 — Diğer Elektronik ✅

**Alanlar:**

| Alan       | Tip           | Detay                  |
|------------|---------------|------------------------|
| Title      | Serbest metin | Kullanıcı elle girer   |
| Marka      | Dropdown      | —                      |
| Model      | Dropdown      | Markaya göre filtreli  |
| Kondisyon  | Dropdown      | Aşağıya bak            |
| Lokasyon   | Mevcut sistem | —                      |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

## 2. VASITA ✅

### Alt Kategoriler (taslak)

| #  | Ad                             | Slug                  |
|----|--------------------------------|-----------------------|
| 01 | Otomobil                       | otomobil              |
| 02 | Motosiklet                     | motosiklet            |
| 03 | Elektrikli Araç & Scooter      | elektrikli-arac       |
| 04 | Kamyonet & Minibüs             | kamyonet-minibus      |
| 05 | Kamyon & Tır                   | kamyon-tir            |
| 06 | Traktör & İş Makinesi          | traktor-is-makinesi   |
| 07 | Tekne & Su Aracı               | tekne-su-araci        |
| 08 | Karavan & Kamp Aracı           | karavan               |
| 09 | Yedek Parça & Aksesuar         | vasita-yedek-parca    |

### 2.01 — Otomobil ✅

**Alanlar (bağımlılık sırasına göre):**

| Sıra | Alan       | Tip               | Bağımlı Olduğu | Detay                                                              |
|------|------------|-------------------|-----------------|---------------------------------------------------------------------|
| 1    | Title      | Serbest metin     | —               | Kullanıcı elle girer                                                |
| 2    | Marka      | Dropdown          | —               | —                                                                   |
| 3    | Model      | Dropdown          | Marka           | Markaya göre filtreli                                               |
| 4    | Yıl        | Dropdown          | —               | 1990'dan günümüze                                                   |
| 5    | Kilometre  | Serbest metin     | —               | Formatlı giriş: 10.000 stili                                        |
| 6    | Yakıt      | Dropdown          | —               | Benzin / Dizel / LPG / Hibrit / Elektrik                           |
| 7    | Vites      | Dropdown          | —               | Manuel / Otomatik / Yarı Otomatik                                   |
| 8    | Kasa Tipi  | Dropdown          | —               | Sedan / Hatchback / SUV / Crossover / Pickup / Minivan / Cabrio    |
| 9    | Hasar      | Dropdown          | —               | Hasar Kayıtsız / Hasar Kayıtlı / Pert Kayıtlı                      |
| 10   | Kondisyon  | Dropdown          | —               | Aşağıya bak                                                         |
| 11   | Lokasyon   | Mevcut sistem     | —               | —                                                                   |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.02 — Motosiklet ✅

**Alanlar (bağımlılık sırasına göre):**

| Sıra | Alan        | Tip           | Bağımlı Olduğu | Detay                                                      |
|------|-------------|---------------|-----------------|-------------------------------------------------------------|
| 1    | Title       | Serbest metin | —               | Kullanıcı elle girer                                        |
| 2    | Marka       | Dropdown      | —               | Honda / Yamaha / Kawasaki / Suzuki / BMW / KTM / Vespa / Diğer |
| 3    | Model       | Serbest metin | —               | —                                                           |
| 4    | Tip         | Dropdown      | —               | Naked / Sport / Touring / Enduro / Scooter / Klasik        |
| 5    | Yıl         | Dropdown      | —               | 1990–2025                                                   |
| 6    | Kilometre   | Serbest metin | —               | Formatlı giriş: 10.000 stili                                |
| 7    | Motor Hacmi | Dropdown      | —               | 50cc / 125cc / 250cc / 400cc / 600cc / 750cc / 1000cc+    |
| 8    | Kondisyon   | Dropdown      | —               | Aşağıya bak                                                 |
| 9    | Lokasyon    | Mevcut sistem | —               | —                                                           |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.03 — Elektrikli Araç & Scooter ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                                                    |
|------|------------|---------------|------------------------------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Kullanıcı elle girer                                                                     |
| 2    | Marka      | Dropdown      | Xiaomi / Segway / Ninebot / Vestel / Niu / Diğer                                         |
| 3    | Model      | Serbest metin | —                                                                                        |
| 4    | Tip        | Dropdown      | Elektrikli Scooter / Elektrikli Bisiklet / Elektrikli Motosiklet / Hoverboard / Diğer   |
| 5    | Menzil     | Dropdown      | 0-20 km / 20-40 km / 40-60 km / 60-80 km / 80 km+                                      |
| 6    | Kilometre  | Serbest metin | Formatlı, 10.000 stili — opsiyonel                                                       |
| 7    | Kondisyon  | Dropdown      | Aşağıya bak                                                                              |
| 8    | Lokasyon   | Mevcut sistem | —                                                                                        |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.04 — Kamyonet & Minibüs ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                                   |
|------|------------|---------------|-------------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Kullanıcı elle girer                                                    |
| 2    | Marka      | Dropdown      | Ford / Fiat / Mercedes / Volkswagen / Renault / Peugeot / Toyota / Diğer |
| 3    | Model      | Dropdown      | Markaya göre filtreli                                                   |
| 4    | Tip        | Dropdown      | Kamyonet / Minibüs / Panelvan / Pick-up / Frigorifik                   |
| 5    | Yıl        | Dropdown      | 1990–2025                                                               |
| 6    | Kilometre  | Serbest metin | Formatlı, 10.000 stili                                                  |
| 7    | Yakıt      | Dropdown      | Benzin / Dizel / LPG / Elektrik                                         |
| 8    | Vites      | Dropdown      | Manuel / Otomatik                                                       |
| 9    | Hasar      | Dropdown      | Hasar Kayıtsız / Hasar Kayıtlı / Pert Kayıtlı                          |
| 10   | Kondisyon  | Dropdown      | Aşağıya bak                                                             |
| 11   | Lokasyon   | Mevcut sistem | —                                                                       |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.05 — Kamyon & Tır ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                               |
|------|------------|---------------|---------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Kullanıcı elle girer                                                |
| 2    | Marka      | Dropdown      | Mercedes / MAN / Volvo / DAF / Scania / Iveco / Ford / Diğer       |
| 3    | Model      | Dropdown      | Markaya göre filtreli                                               |
| 4    | Tip        | Dropdown      | Kamyon / Tır / Çekici / Damperli / Frigorifik / Tanker             |
| 5    | Yıl        | Dropdown      | 1990–2025                                                           |
| 6    | Kilometre  | Serbest metin | Formatlı, 10.000 stili                                              |
| 7    | Yakıt      | Dropdown      | Dizel / LNG / Elektrik                                              |
| 8    | Vites      | Dropdown      | Manuel (default) / Otomatik                                         |
| 9    | Hasar      | Dropdown      | Hasar Kayıtsız / Hasar Kayıtlı / Pert Kayıtlı                      |
| 10   | Kondisyon  | Dropdown      | Aşağıya bak                                                         |
| 11   | Lokasyon   | Mevcut sistem | —                                                                   |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.06 — Traktör & İş Makinesi ✅

**Alanlar:**

| Sıra | Alan           | Tip           | Detay                                                                           |
|------|----------------|---------------|---------------------------------------------------------------------------------|
| 1    | Title          | Serbest metin | Kullanıcı elle girer                                                            |
| 2    | Marka          | Dropdown      | John Deere / New Holland / Massey Ferguson / Case / Fendt / Türk Traktör / Diğer |
| 3    | Model          | Dropdown      | Markaya göre filtreli                                                           |
| 4    | Tip            | Dropdown      | Traktör / Biçerdöver / Ekskavatör / Forklift / Yükleyici / Greyder / Diğer     |
| 5    | Yıl            | Dropdown      | 1980–2025                                                                       |
| 6    | Çalışma Saati  | Serbest metin | Formatlı, 1.000 stili — opsiyonel                                               |
| 7    | Kilometre      | Serbest metin | Formatlı, 10.000 stili — opsiyonel                                              |
| 8    | Kondisyon      | Dropdown      | Aşağıya bak                                                                     |
| 9    | Lokasyon       | Mevcut sistem | —                                                                               |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.07 — Tekne & Su Aracı ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                                                          |
|------|------------|---------------|------------------------------------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Kullanıcı elle girer                                                                           |
| 2    | Marka      | Dropdown      | Bayliner / Jeanneau / Beneteau / Zodiac / Yamaha / Diğer                                      |
| 3    | Model      | Dropdown      | Markaya göre filtreli                                                                          |
| 4    | Tip        | Dropdown      | Motorlu Tekne / Yelkenli / Jet Ski / Şişme Bot / Balıkçı Teknesi / Yat / Diğer               |
| 5    | Yıl        | Dropdown      | 1980–2025                                                                                      |
| 6    | Uzunluk    | Serbest metin | Metre cinsinden — nokta ile başlayamaz, noktadan önce max 3 rakam, sonra max 2 rakam (örn. 12.50) |
| 7    | Kondisyon  | Dropdown      | Aşağıya bak                                                                                    |
| 8    | Lokasyon   | Mevcut sistem | —                                                                                              |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.08 — Karavan & Kamp Aracı ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                        |
|------|------------|---------------|--------------------------------------------------------------|
| 1    | Title      | Serbest metin | Kullanıcı elle girer                                         |
| 2    | Marka      | Dropdown      | Hobby / Knaus / Dethleffs / Bürstner / Hymer / Diğer        |
| 3    | Model      | Dropdown      | Markaya göre filtreli                                        |
| 4    | Tip        | Dropdown      | Karavan / Motorhome / Çekme Karavan / Kamp Aracı            |
| 5    | Yıl        | Dropdown      | 1990–2025                                                    |
| 6    | Kilometre  | Serbest metin | Formatlı, 10.000 stili — opsiyonel                           |
| 7    | Kondisyon  | Dropdown      | Aşağıya bak                                                  |
| 8    | Lokasyon   | Mevcut sistem | —                                                            |

**Kondisyonlar:** Sıfır · İkinci El

---

### 2.09 — Yedek Parça & Aksesuar ✅

**Alanlar:**

| Sıra | Alan        | Tip           | Detay                                                                                               |
|------|-------------|---------------|-----------------------------------------------------------------------------------------------------|
| 1    | Title       | Serbest metin | Kullanıcı elle girer                                                                                |
| 2    | Araç Tipi   | Dropdown      | Otomobil / Motosiklet / Kamyon & Tır / Elektrikli Araç / Diğer                                    |
| 3    | Marka Uyumu | Dropdown      | Ürünün uyduğu araç markası — opsiyonel                                                             |
| 4    | Parça Tipi  | Dropdown      | Motor & Şanzıman / Karoseri / Elektrik & Aydınlatma / Fren & Süspansiyon / İç Aksesuar / Lastik & Jant / Diğer |
| 5    | Kondisyon   | Dropdown      | Aşağıya bak                                                                                         |
| 6    | Lokasyon    | Mevcut sistem | —                                                                                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El · Hasarlı

---

## 3. EMLAK ✅

### Alt Kategoriler (taslak)

| #  | Ad                    | Slug              |
|----|-----------------------|-------------------|
| 01 | Daire                 | daire             |
| 02 | Müstakil Ev & Villa   | mustakil-ev-villa |
| 03 | Arsa                  | arsa              |
| 04 | Tarla & Bahçe         | tarla-bahce       |
| 05 | İş Yeri & Ofis        | is-yeri-ofis      |
| 06 | Depo & Fabrika        | depo-fabrika      |
| 07 | Bina                  | bina              |

### 3.01 — Daire ✅

**Alanlar:**

| Sıra | Alan         | Tip           | Detay                                                     |
|------|--------------|---------------|-----------------------------------------------------------|
| 1    | Title        | Serbest metin | Kullanıcı elle girer                                      |
| 2    | İlan Tipi    | Dropdown      | Satılık / Kiralık                                         |
| 3    | Oda Sayısı   | Dropdown      | Stüdyo / 1+1 / 2+1 / 3+1 / 4+1 / 5+1 / 5+              |
| 4    | Brüt m²      | Serbest metin | Yalnızca sayı, max 5 rakam                                |
| 5    | Net m²       | Serbest metin | Opsiyonel                                                 |
| 6    | Kat          | Serbest metin | Yalnızca sayı (Zemin için 0)                              |
| 7    | Bina Yaşı    | Dropdown      | Sıfır / 1-5 yıl / 5-10 yıl / 10-20 yıl / 20+ yıl       |
| 8    | Isıtma       | Dropdown      | Kombi / Merkezi / Kat Kaloriferi / Klima / Yerden / Yok  |
| 9    | Eşya Durumu  | Dropdown      | Eşyalı / Eşyasız / Yarı Eşyalı                          |
| 10   | Asansör      | Dropdown      | Var / Yok                                                 |
| 11   | Otopark      | Dropdown      | Kapalı / Açık / Yok                                       |
| 12   | Kondisyon    | Dropdown      | Sıfır / İkinci El                                         |
| 13   | Lokasyon     | Mevcut sistem | —                                                         |

---

### 3.02 — Müstakil Ev & Villa ✅

**Alanlar:**

| Sıra | Alan         | Tip           | Detay                                                     |
|------|--------------|---------------|-----------------------------------------------------------|
| 1    | Title        | Serbest metin | Kullanıcı elle girer                                      |
| 2    | İlan Tipi    | Dropdown      | Satılık / Kiralık                                         |
| 3    | Tip          | Dropdown      | Müstakil Ev / Villa / Köy Evi / Çiftlik Evi              |
| 4    | Oda Sayısı   | Dropdown      | 1+1 / 2+1 / 3+1 / 4+1 / 5+1 / 5+                       |
| 5    | Brüt m²      | Serbest metin | Yalnızca sayı, max 5 rakam                                |
| 6    | Net m²       | Serbest metin | Opsiyonel                                                 |
| 7    | Arsa m²      | Serbest metin | Opsiyonel                                                 |
| 8    | Bina Yaşı    | Dropdown      | Sıfır / 1-5 yıl / 5-10 yıl / 10-20 yıl / 20+ yıl       |
| 9    | Isıtma       | Dropdown      | Kombi / Merkezi / Kat Kaloriferi / Klima / Yerden / Yok  |
| 10   | Eşya Durumu  | Dropdown      | Eşyalı / Eşyasız / Yarı Eşyalı                          |
| 11   | Havuz        | Dropdown      | Var / Yok                                                 |
| 12   | Otopark      | Dropdown      | Kapalı / Açık / Yok                                       |
| 13   | Kondisyon    | Dropdown      | Sıfır / İkinci El                                         |
| 14   | Lokasyon     | Mevcut sistem | —                                                         |

---

### 3.03 — Arsa ✅

**Alanlar:**

| Sıra | Alan        | Tip           | Detay                                              |
|------|-------------|---------------|----------------------------------------------------|
| 1    | Title       | Serbest metin | Kullanıcı elle girer                               |
| 2    | İlan Tipi   | Dropdown      | Satılık / Kiralık                                  |
| 3    | m²          | Serbest metin | Yalnızca sayı, max 7 rakam                         |
| 4    | İmar Durumu | Dropdown      | İmarlı / İmarsız / Konut İmarlı / Ticari İmarlı   |
| 5    | Tapu Durumu | Dropdown      | Kat Mülkiyeti / Kat İrtifakı / Hisseli / Müstakil |
| 6    | Lokasyon    | Mevcut sistem | —                                                  |

*(Kondisyon alanı yok — arsada anlamsız)*

---

### 3.04 — Tarla & Bahçe ✅

**Alanlar:**

| Sıra | Alan        | Tip           | Detay                                                    |
|------|-------------|---------------|----------------------------------------------------------|
| 1    | Title       | Serbest metin | Kullanıcı elle girer                                     |
| 2    | İlan Tipi   | Dropdown      | Satılık / Kiralık                                        |
| 3    | Tip         | Dropdown      | Tarla / Bahçe / Zeytinlik / Bağ / Meyve Bahçesi / Diğer |
| 4    | m²          | Serbest metin | Yalnızca sayı, max 9 rakam                               |
| 5    | İmar Durumu | Dropdown      | İmarlı / İmarsız / Tarım Arazisi / Orman Vasfı          |
| 6    | Sulama      | Dropdown      | Sulak / Kuru — opsiyonel                                 |
| 7    | Lokasyon    | Mevcut sistem | —                                                        |

---

### 3.05 — İş Yeri & Ofis ✅

**Alanlar:**

| Sıra | Alan         | Tip           | Detay                                                     |
|------|--------------|---------------|-----------------------------------------------------------|
| 1    | Title        | Serbest metin | Kullanıcı elle girer                                      |
| 2    | İlan Tipi    | Dropdown      | Satılık / Kiralık                                         |
| 3    | Tip          | Dropdown      | Ofis / Dükkan / Restoran & Kafe / Depo / Atölye / Diğer |
| 4    | Brüt m²      | Serbest metin | Yalnızca sayı, max 6 rakam                                |
| 5    | Net m²       | Serbest metin | Opsiyonel                                                 |
| 6    | Kat          | Serbest metin | Yalnızca sayı (Zemin için 0)                              |
| 7    | Bina Yaşı    | Dropdown      | Sıfır / 1-5 yıl / 5-10 yıl / 10-20 yıl / 20+ yıl       |
| 8    | Isıtma       | Dropdown      | Kombi / Merkezi / Klima / Yerden / Yok                   |
| 9    | Eşya Durumu  | Dropdown      | Eşyalı / Eşyasız — opsiyonel                             |
| 10   | Otopark      | Dropdown      | Kapalı / Açık / Yok                                      |
| 11   | Kondisyon    | Dropdown      | Sıfır / İkinci El                                         |
| 12   | Lokasyon     | Mevcut sistem | —                                                         |

---

### 3.06 — Depo & Fabrika ✅

**Alanlar:**

| Sıra | Alan             | Tip           | Detay                                                  |
|------|------------------|---------------|--------------------------------------------------------|
| 1    | Title            | Serbest metin | Kullanıcı elle girer                                   |
| 2    | İlan Tipi        | Dropdown      | Satılık / Kiralık                                      |
| 3    | Tip              | Dropdown      | Depo / Fabrika / Hangar / Soğuk Hava Deposu / Diğer   |
| 4    | Brüt m²          | Serbest metin | Yalnızca sayı, max 7 rakam                             |
| 5    | Tavan Yüksekliği | Dropdown      | 3-5m / 5-8m / 8-12m / 12m+                            |
| 6    | Bina Yaşı        | Dropdown      | Sıfır / 1-5 yıl / 5-10 yıl / 10-20 yıl / 20+ yıl     |
| 7    | Kondisyon        | Dropdown      | Sıfır / İkinci El                                      |
| 8    | Lokasyon         | Mevcut sistem | —                                                      |

---

### 3.07 — Bina ✅

**Alanlar:**

| Sıra | Alan         | Tip           | Detay                                                  |
|------|--------------|---------------|--------------------------------------------------------|
| 1    | Title        | Serbest metin | Kullanıcı elle girer                                   |
| 2    | İlan Tipi    | Dropdown      | Satılık / Kiralık                                      |
| 3    | Tip          | Dropdown      | Apartman / Rezidans / Ticari Bina / Karma Kullanım / Diğer |
| 4    | Toplam m²    | Serbest metin | Yalnızca sayı, max 7 rakam                             |
| 5    | Kat Sayısı   | Serbest metin | Yalnızca sayı, max 2 rakam                             |
| 6    | Daire Sayısı | Serbest metin | Yalnızca sayı, max 4 rakam — opsiyonel                 |
| 7    | Bina Yaşı    | Dropdown      | Sıfır / 1-5 yıl / 5-10 yıl / 10-20 yıl / 20+ yıl     |
| 8    | Kondisyon    | Dropdown      | Sıfır / İkinci El                                      |
| 9    | Lokasyon     | Mevcut sistem | —                                                      |

---

## 4. GİYİM & AKSESUAR ✅

### Alt Kategoriler (taslak)

| #  | Ad                         | Slug                   |
|----|----------------------------|------------------------|
| 01 | Kadın Giyim                | kadin-giyim            |
| 02 | Erkek Giyim                | erkek-giyim            |
| 03 | Çocuk & Bebek Giyim        | cocuk-bebek-giyim      |
| 04 | Ayakkabı                   | ayakkabi               |
| 05 | Çanta & Cüzdan             | canta-cuzdan           |
| 06 | Takı & Mücevher            | taki-mucevher          |
| 07 | Saat                       | saat                   |
| 08 | Şapka, Kemer & Aksesuar    | sapka-kemer-aksesuar   |

### 4.01 — Kadın Giyim ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                  |
|------|-----------|---------------|----------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                   |
| 2    | Tip       | Dropdown      | Elbise / Bluz & Gömlek / Pantolon & Etek / Mont & Kaban / Kazak & Hırka / Takım Elbise / İç Giyim / Diğer |
| 3    | Marka     | Dropdown      | Zara / H&M / Mango / Koton / LC Waikiki / Bershka / Diğer                             |
| 4    | Beden     | Dropdown      | XS / S / M / L / XL / XXL / 3XL                                                       |
| 5    | Kondisyon | Dropdown      | Aşağıya bak                                                                            |
| 6    | Lokasyon  | Mevcut sistem | —                                                                                      |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.02 — Erkek Giyim ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                         |
|------|-----------|---------------|-----------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                          |
| 2    | Tip       | Dropdown      | Gömlek / Tişört / Pantolon & Şort / Mont & Kaban / Kazak & Hırka / Takım Elbise / İç Giyim / Diğer |
| 3    | Marka     | Dropdown      | Zara / H&M / Koton / LC Waikiki / Mavi / Pull&Bear / Diğer                                   |
| 4    | Beden     | Dropdown      | XS / S / M / L / XL / XXL / 3XL                                                              |
| 5    | Kondisyon | Dropdown      | Aşağıya bak                                                                                   |
| 6    | Lokasyon  | Mevcut sistem | —                                                                                             |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.03 — Çocuk & Bebek Giyim ✅

**Alanlar:**

| Sıra | Alan        | Tip           | Detay                                                                                              |
|------|-------------|---------------|----------------------------------------------------------------------------------------------------|
| 1    | Title       | Serbest metin | Kullanıcı elle girer                                                                               |
| 2    | Cinsiyet    | Dropdown      | Kız / Erkek / Unisex                                                                               |
| 3    | Tip         | Dropdown      | Takım & Tulum / Üst Giyim / Alt Giyim / Mont & Kaban / İç Giyim / Diğer                          |
| 4    | Marka       | Dropdown      | LC Waikiki / Zara Kids / H&M Kids / Koton Kids / Defacto / Diğer                                  |
| 5    | Yaş / Beden | Dropdown      | 0-3 ay / 3-6 ay / 6-12 ay / 1-2 yaş / 2-3 yaş / 4-5 yaş / 6-7 yaş / 8-9 yaş / 10-11 yaş / 12-14 yaş |
| 6    | Kondisyon   | Dropdown      | Aşağıya bak                                                                                        |
| 7    | Lokasyon    | Mevcut sistem | —                                                                                                  |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.04 — Ayakkabı ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                       |
|------|-----------|---------------|-----------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                        |
| 2    | Cinsiyet  | Dropdown      | Kadın / Erkek / Unisex / Çocuk                                              |
| 3    | Marka     | Dropdown      | Nike / Adidas / Puma / New Balance / Converse / Skechers / Diğer            |
| 4    | Tip       | Dropdown      | Spor / Günlük / Topuklu / Bot & Çizme / Sandalet & Terlik / Klasik / Diğer |
| 5    | Numara    | Dropdown      | 35 / 36 / 37 / 38 / 39 / 40 / 41 / 42 / 43 / 44 / 45 / 46+               |
| 6    | Kondisyon | Dropdown      | Aşağıya bak                                                                 |
| 7    | Lokasyon  | Mevcut sistem | —                                                                           |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.05 — Çanta & Cüzdan ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                               |
|------|-----------|---------------|---------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                |
| 2    | Cinsiyet  | Dropdown      | Kadın / Erkek / Unisex                                              |
| 3    | Marka     | Dropdown      | Louis Vuitton / Gucci / Michael Kors / Zara / Koton / Diğer        |
| 4    | Tip       | Dropdown      | Omuz Çantası / Sırt Çantası / El Çantası / Cüzdan / Valiz / Diğer |
| 5    | Kondisyon | Dropdown      | Aşağıya bak                                                         |
| 6    | Lokasyon  | Mevcut sistem | —                                                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.06 — Takı & Mücevher ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Bağımlılık | Detay                                                                                               |
|------|-----------|---------------|------------|-----------------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | —          | Kullanıcı elle girer                                                                                |
| 2    | Tip       | Dropdown      | —          | Yüzük / Kolye / Bileklik / Küpe / Bilezik / Set / Diğer                                            |
| 3    | Malzeme   | Dropdown      | —          | Altın / Gümüş / Rose Gold / Platin / Çelik / Diğer                                                 |
| 4    | Ayar      | Dropdown      | Malzeme    | Altın & Rose Gold → 8/14/18/22/24 Ayar · Gümüş → 800/925 Ayar · Platin/Çelik/Diğer → gizli      |
| 5    | Kondisyon | Dropdown      | —          | Aşağıya bak                                                                                         |
| 6    | Lokasyon  | Mevcut sistem | —          | —                                                                                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.07 — Saat ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                               |
|------|-----------|---------------|---------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                |
| 2    | Marka     | Dropdown      | Rolex / Omega / Casio / Seiko / Tissot / Fossil / Swatch / Diğer   |
| 3    | Model     | Dropdown      | Markaya göre filtreli                                               |
| 4    | Tip       | Dropdown      | Mekanik / Otomatik / Kuvars / Akıllı Saat / Diğer                  |
| 5    | Cinsiyet  | Dropdown      | Erkek / Kadın / Unisex                                              |
| 6    | Kondisyon | Dropdown      | Aşağıya bak                                                         |
| 7    | Lokasyon  | Mevcut sistem | —                                                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 4.08 — Şapka, Kemer & Aksesuar ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                         |
|------|-----------|---------------|---------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                          |
| 2    | Tip       | Dropdown      | Şapka / Kemer / Eşarp & Atkı / Gözlük / Eldiven / Diğer     |
| 3    | Marka     | Dropdown      | Opsiyonel                                                     |
| 4    | Cinsiyet  | Dropdown      | Kadın / Erkek / Unisex                                        |
| 5    | Kondisyon | Dropdown      | Aşağıya bak                                                   |
| 6    | Lokasyon  | Mevcut sistem | —                                                             |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

## 5. EV & YAŞAM ✅

### Alt Kategoriler (taslak)

| #  | Ad                          | Slug                   |
|----|-----------------------------|------------------------|
| 01 | Mobilya                     | mobilya                |
| 02 | Mutfak & Pişirme Gereçleri  | mutfak-pisirme         |
| 03 | Ev Tekstili                 | ev-tekstili            |
| 04 | Dekorasyon & Aydınlatma     | dekorasyon-aydinlatma  |
| 05 | Bahçe & Balkon              | bahce-balkon           |
| 06 | Bebek & Çocuk Odası         | bebek-cocuk-odasi      |
| 07 | Yapı & Tadilat Malzemeleri  | yapi-tadilat           |
| 08 | Diğer Ev Eşyası             | diger-ev-esyasi        |

### 5.01 — Mobilya ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                        |
|------|-----------|---------------|----------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                         |
| 2    | Tip       | Dropdown      | Koltuk & Kanepe / Yatak & Baza / Masa & Sandalye / Dolap & Şifonyer / Raf & Kitaplık / Diğer |
| 3    | Marka     | Dropdown      | İkea / Bellona / İstikbal / Çilek / Diğer — opsiyonel                                       |
| 4    | Malzeme   | Dropdown      | Ahşap / MDF / Metal / Cam / Kumaş / Deri / Diğer — opsiyonel                                |
| 5    | Kondisyon | Dropdown      | Aşağıya bak                                                                                  |
| 6    | Lokasyon  | Mevcut sistem | —                                                                                            |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.02 — Mutfak & Pişirme Gereçleri ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                    |
|------|-----------|---------------|------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                     |
| 2    | Tip       | Dropdown      | Tencere & Tava / Bıçak & Kesici / Küçük Mutfak Aleti / Sofra Takımı / Saklama Kabı / Diğer |
| 3    | Marka     | Dropdown      | Tefal / Korkmaz / Fakir / Arçelik / Karaca / Diğer — opsiyonel                          |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                              |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                        |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.03 — Ev Tekstili ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                             |
|------|-----------|---------------|-----------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                              |
| 2    | Tip       | Dropdown      | Nevresim Takımı / Yorgan & Battaniye / Havlu & Bornoz / Perde / Halı & Kilim / Diğer |
| 3    | Marka     | Dropdown      | Madame Coco / English Home / Taç / Özdilek / Diğer — opsiyonel                   |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                       |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                 |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.04 — Dekorasyon & Aydınlatma ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                             |
|------|-----------|---------------|-----------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                              |
| 2    | Tip       | Dropdown      | Tablo & Tablo Çerçeve / Vazo & Saksı / Avize & Lamba / Ayna / Mum & Mumluk / Diğer |
| 3    | Kondisyon | Dropdown      | Aşağıya bak                                                                       |
| 4    | Lokasyon  | Mevcut sistem | —                                                                                 |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.05 — Bahçe & Balkon ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                             |
|------|-----------|---------------|-----------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                              |
| 2    | Tip       | Dropdown      | Bahçe Mobilyası / Saksı & Bitki / Bahçe Aleti / Sulama Sistemi / Barbekü / Diğer |
| 3    | Kondisyon | Dropdown      | Aşağıya bak                                                                       |
| 4    | Lokasyon  | Mevcut sistem | —                                                                                 |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.06 — Bebek & Çocuk Odası ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                      |
|------|-----------|---------------|--------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                       |
| 2    | Tip       | Dropdown      | Bebek Arabası / Bebek Yatağı & Beşik / Mama Sandalyesi / Çocuk Mobilyası / Oyun Parkı / Diğer |
| 3    | Marka     | Dropdown      | Chicco / Graco / Maxi-Cosi / Joie / Cybex / Diğer — opsiyonel                             |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                                |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                          |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.07 — Yapı & Tadilat Malzemeleri ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                              |
|------|-----------|---------------|----------------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                               |
| 2    | Tip       | Dropdown      | Boya & Kaplama / Zemin & Duvar Kaplaması / Elektrik Malzemesi / Sıhhi Tesisat / El Aleti & Makine / Diğer |
| 3    | Kondisyon | Dropdown      | Aşağıya bak                                                                                        |
| 4    | Lokasyon  | Mevcut sistem | —                                                                                                  |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 5.08 — Diğer Ev Eşyası ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                               |
|------|-----------|---------------|-------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                |
| 2    | Kondisyon | Dropdown      | Aşağıya bak                         |
| 3    | Lokasyon  | Mevcut sistem | —                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

## 6. SPOR & OUTDOOR ✅

### Alt Kategoriler (taslak)

| #  | Ad                       | Slug                  |
|----|--------------------------|-----------------------|
| 01 | Fitness & Spor Salonu    | fitness-spor-salonu   |
| 02 | Bisiklet                 | bisiklet              |
| 03 | Outdoor & Kamp           | outdoor-kamp          |
| 04 | Su Sporları              | su-sporlari           |
| 05 | Top & Takım Sporları     | takim-sporlari        |
| 06 | Kış Sporları             | kis-sporlari          |
| 07 | Yoga & Pilates           | yoga-pilates          |
| 08 | Diğer Spor               | diger-spor            |

### 6.01 — Fitness & Spor Salonu ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                        |
|------|-----------|---------------|----------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                         |
| 2    | Tip       | Dropdown      | Ağırlık & Halter / Koşu Bandı / Kondisyon Bisikleti / Kürek Makinesi / Pilates Aleti / Diğer |
| 3    | Marka     | Dropdown      | Technogym / Life Fitness / Tunturi / Kettler / Diğer — opsiyonel                             |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                                  |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                            |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.02 — Bisiklet ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                                                   |
|------|------------|---------------|-----------------------------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Kullanıcı elle girer                                                                    |
| 2    | Marka      | Dropdown      | Trek / Giant / Specialized / Bianchi / Decathlon / Diğer                                |
| 3    | Tip        | Dropdown      | Dağ Bisikleti / Yol Bisikleti / Şehir Bisikleti / BMX / Elektrikli / Çocuk / Diğer    |
| 4    | Jant       | Dropdown      | 12" / 14" / 16" / 18" / 20" / 24" / 26" / 27.5" / 28" / 29"                          |
| 5    | Kadro Boyu | Dropdown      | XS / S / M / L / XL — opsiyonel                                                        |
| 6    | Kondisyon  | Dropdown      | Aşağıya bak                                                                             |
| 7    | Lokasyon   | Mevcut sistem | —                                                                                       |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.03 — Outdoor & Kamp ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                             |
|------|-----------|---------------|-----------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                              |
| 2    | Tip       | Dropdown      | Çadır / Uyku Tulumu / Sırt Çantası / Trekking Botu / Kamp Mutfak & Ekipmanı / Diğer |
| 3    | Marka     | Dropdown      | The North Face / Quechua / Columbia / Mammut / Diğer — opsiyonel                 |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                       |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                 |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.04 — Su Sporları ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                  |
|------|-----------|---------------|----------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                   |
| 2    | Tip       | Dropdown      | Sörf Tahtası / Dalış Ekipmanı / Kano & Kayak / Yüzme Malzemesi / Yelken Ekipmanı / Diğer |
| 3    | Marka     | Dropdown      | Decathlon / Cressi / Mistral / Diğer — opsiyonel                                       |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                            |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                      |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.05 — Top & Takım Sporları ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Bağımlılık | Detay                                                                                                      |
|------|-----------|---------------|------------|------------------------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | —          | Kullanıcı elle girer                                                                                       |
| 2    | Spor Dalı | Dropdown      | —          | Futbol / Basketbol / Voleybol / Tenis & Padel / Badminton / Boks & Dövüş / Diğer                          |
| 3    | Tip       | Dropdown      | Spor Dalı  | Futbol→Top/Forma/Krampon/Tekmelik · Basketbol→Top/Forma/Ayakkabı · Tenis→Raket/Top/Forma · vb.            |
| 4    | Marka     | Dropdown      | Spor Dalı  | Futbol→Nike/Adidas/Puma · Tenis→Wilson/Head/Babolat · Badminton→Yonex/Victor · Boks→Everlast/Venum · vb.  |
| 5    | Kondisyon | Dropdown      | —          | Aşağıya bak                                                                                                |
| 6    | Lokasyon  | Mevcut sistem | —          | —                                                                                                          |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.06 — Kış Sporları ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                               |
|------|-----------|---------------|---------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                |
| 2    | Tip       | Dropdown      | Kayak Takımı / Snowboard / Kayak Botu / Kask & Gözlük / Kıyafet / Diğer |
| 3    | Marka     | Dropdown      | Rossignol / Head / Atomic / Burton / Salomon / Diğer — opsiyonel   |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                         |
| 5    | Lokasyon  | Mevcut sistem | —                                                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.07 — Yoga & Pilates ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                               |
|------|-----------|---------------|---------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                |
| 2    | Tip       | Dropdown      | Yoga Matı / Pilates Topu / Pilates Bandı / Blok & Aksesuar / Diğer |
| 3    | Marka     | Dropdown      | Manduka / Lululemon / Decathlon / Diğer — opsiyonel                 |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                         |
| 5    | Lokasyon  | Mevcut sistem | —                                                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 6.08 — Diğer Spor ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                               |
|------|-----------|---------------|-------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                |
| 2    | Kondisyon | Dropdown      | Aşağıya bak                         |
| 3    | Lokasyon  | Mevcut sistem | —                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

## 7. KİTAP & HOBİ ✅

### Alt Kategoriler (taslak)

| #  | Ad                              | Slug                   |
|----|---------------------------------|------------------------|
| 01 | Roman & Hikaye                  | roman-hikaye           |
| 02 | Ders Kitabı & Akademik          | ders-kitabi-akademik   |
| 03 | Çocuk Kitabı                    | cocuk-kitabi           |
| 04 | Kişisel Gelişim                 | kisisel-gelisim        |
| 05 | Müzik Aleti                     | muzik-aleti            |
| 06 | Koleksiyon                      | koleksiyon             |
| 07 | El Sanatı & Sanat Malzemeleri   | el-sanati-sanat        |
| 08 | CD, DVD & Oyun                  | cd-dvd-oyun            |
| 09 | Diğer Kitap & Hobi              | diger-kitap-hobi       |

### 7.01 — Roman & Hikaye ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                                    |
|------|------------|---------------|--------------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Genel ilan başlığı                                                       |
| 2    | Kitap İsmi | Serbest metin | Eserin tam adı                                                           |
| 3    | Yazar      | Serbest metin | Opsiyonel                                                                |
| 4    | Yayınevi   | Dropdown      | İş Bankası / Can / Doğan / Yapı Kredi / Epsilon / Diğer — opsiyonel     |
| 5    | Dil        | Dropdown      | Türkçe / İngilizce / Diğer                                               |
| 6    | Kondisyon  | Dropdown      | Aşağıya bak                                                              |
| 7    | Lokasyon   | Mevcut sistem | —                                                                        |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.02 — Ders Kitabı & Akademik ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                                                                          |
|------|------------|---------------|------------------------------------------------------------------------------------------------|
| 1    | Title      | Serbest metin | Genel ilan başlığı                                                                             |
| 2    | Kitap İsmi | Serbest metin | Eserin tam adı                                                                                 |
| 3    | Yazar      | Serbest metin | Opsiyonel                                                                                      |
| 4    | Konu       | Dropdown      | Matematik / Fizik / Kimya / Biyoloji / Tarih / Dil & Edebiyat / Hukuk / Tıp / Mühendislik / Diğer |
| 5    | Seviye     | Dropdown      | İlkokul / Ortaokul / Lise / Üniversite / YKS & Sınav / Diğer                                 |
| 6    | Dil        | Dropdown      | Türkçe / İngilizce / Diğer                                                                     |
| 7    | Kondisyon  | Dropdown      | Aşağıya bak                                                                                    |
| 8    | Lokasyon   | Mevcut sistem | —                                                                                              |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.03 — Çocuk Kitabı ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                                  |
|------|------------|---------------|----------------------------------------|
| 1    | Title      | Serbest metin | Genel ilan başlığı                     |
| 2    | Kitap İsmi | Serbest metin | Eserin tam adı                         |
| 3    | Yaş Grubu  | Dropdown      | 0-2 yaş / 3-5 yaş / 6-8 yaş / 9-12 yaş |
| 4    | Dil        | Dropdown      | Türkçe / İngilizce / Diğer             |
| 5    | Kondisyon  | Dropdown      | Aşağıya bak                            |
| 6    | Lokasyon   | Mevcut sistem | —                                      |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.04 — Kişisel Gelişim ✅

**Alanlar:**

| Sıra | Alan       | Tip           | Detay                               |
|------|------------|---------------|-------------------------------------|
| 1    | Title      | Serbest metin | Genel ilan başlığı                  |
| 2    | Kitap İsmi | Serbest metin | Eserin tam adı                      |
| 3    | Yazar      | Serbest metin | Opsiyonel                           |
| 4    | Dil        | Dropdown      | Türkçe / İngilizce / Diğer          |
| 5    | Kondisyon  | Dropdown      | Aşağıya bak                         |
| 6    | Lokasyon   | Mevcut sistem | —                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.05 — Müzik Aleti ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                         |
|------|-----------|---------------|-----------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                          |
| 2    | Tip       | Dropdown      | Gitar / Bateri & Perküsyon / Klavye & Piyano / Keman & Yaylı / Nefesli / DJ & Prodüksiyon / Diğer |
| 3    | Marka     | Dropdown      | Fender / Gibson / Yamaha / Roland / Ibanez / Diğer — opsiyonel                                |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                                   |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                             |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.06 — Koleksiyon ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                      |
|------|-----------|---------------|--------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                       |
| 2    | Tip       | Dropdown      | Pul & Para / Antika & Vintage / Futbol Kartı & Forma / Oyuncak & Figür / Madalya & Rozet / Diğer |
| 3    | Dönem     | Serbest metin | Opsiyonel (örn. 1950'ler, Osmanlı dönemi)                                                 |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                                |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                          |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.07 — El Sanatı & Sanat Malzemeleri ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                    |
|------|-----------|---------------|------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                     |
| 2    | Tip       | Dropdown      | Boya & Fırça / Çizim Malzemesi / Dikiş & Örgü / Seramik & Çömlek / Ahşap & Reçine / Diğer |
| 3    | Kondisyon | Dropdown      | Aşağıya bak                                                                              |
| 4    | Lokasyon  | Mevcut sistem | —                                                                                        |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.08 — CD, DVD & Oyun ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                          |
|------|-----------|---------------|--------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                           |
| 2    | Tip       | Dropdown      | CD & Müzik / DVD & Film / PC Oyunu / Konsol Oyunu / Diğer                     |
| 3    | Platform  | Dropdown      | PC / PlayStation / Xbox / Nintendo / Diğer — yalnızca Tip=Konsol Oyunu görünür |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                    |
| 5    | Lokasyon  | Mevcut sistem | —                                                                              |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 7.09 — Diğer Kitap & Hobi ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                               |
|------|-----------|---------------|-------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                |
| 2    | Kondisyon | Dropdown      | Aşağıya bak                         |
| 3    | Lokasyon  | Mevcut sistem | —                                   |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

## 8. DİĞER ✅

### Alt Kategoriler (taslak)

| #  | Ad                         | Slug                   |
|----|----------------------------|------------------------|
| 01 | Oyuncak & Çocuk Oyun       | oyuncak-cocuk-oyun     |
| 02 | Bebek & Anne Ürünleri      | bebek-anne-urunleri    |
| 03 | Evcil Hayvan & Aksesuar    | evcil-hayvan           |
| 04 | Sağlık & Güzellik          | saglik-guzellik        |
| 05 | İş & Ofis Malzemeleri      | is-ofis-malzemeleri    |
| 06 | Antika & Vintage           | antika-vintage         |
| 07 | Yiyecek & Tarım Ürünleri   | yiyecek-tarim          |

### 8.01 — Oyuncak & Çocuk Oyun ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                       |
|------|-----------|---------------|---------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                        |
| 2    | Tip       | Dropdown      | Figür & Aksiyon / Lego & Yapboz / Araç & Oyuncak / Bebek & Oyun Seti / Açık Hava Oyuncağı / Diğer |
| 3    | Yaş Grubu | Dropdown      | 0-2 yaş / 3-5 yaş / 6-9 yaş / 10-12 yaş / 12+ yaş                                        |
| 4    | Marka     | Dropdown      | Lego / Barbie / Hot Wheels / Fisher-Price / Diğer — opsiyonel                               |
| 5    | Kondisyon | Dropdown      | Aşağıya bak                                                                                 |
| 6    | Lokasyon  | Mevcut sistem | —                                                                                           |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 8.02 — Bebek & Anne Ürünleri ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                      |
|------|-----------|---------------|--------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                       |
| 2    | Tip       | Dropdown      | Emzirme & Beslenme / Bez & Bakım / Güvenlik & Monitör / Giyim & Aksesuar / Banyo / Diğer |
| 3    | Marka     | Dropdown      | Chicco / Philips Avent / Tommee Tippee / Pampers / Diğer — opsiyonel                      |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                                |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                          |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 8.03 — Evcil Hayvan & Aksesuar ✅

**Alanlar:**

| Sıra | Alan        | Tip           | Detay                                                                                    |
|------|-------------|---------------|------------------------------------------------------------------------------------------|
| 1    | Title       | Serbest metin | Kullanıcı elle girer                                                                     |
| 2    | Hayvan Tipi | Dropdown      | Kedi / Köpek / Kuş / Balık & Akvaryum / Kemirgen / Diğer                                |
| 3    | Tip         | Dropdown      | Mama & Ödül / Kafes & Yaşam Alanı / Tasma & Giysi / Oyuncak / Sağlık & Bakım / Diğer   |
| 4    | Marka       | Dropdown      | Royal Canin / Hills / Pedigree / Whiskas / Diğer — opsiyonel                             |
| 5    | Kondisyon   | Dropdown      | Aşağıya bak                                                                              |
| 6    | Lokasyon    | Mevcut sistem | —                                                                                        |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 8.04 — Sağlık & Güzellik ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                |
|------|-----------|---------------|----------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                 |
| 2    | Tip       | Dropdown      | Cilt Bakımı / Saç Bakımı / Makyaj / Parfüm / Medikal Cihaz / Diğer  |
| 3    | Marka     | Dropdown      | L'Oréal / Nivea / Maybelline / Braun / Philips / Diğer — opsiyonel  |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                          |
| 5    | Lokasyon  | Mevcut sistem | —                                                                    |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 8.05 — İş & Ofis Malzemeleri ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                           |
|------|-----------|---------------|---------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                            |
| 2    | Tip       | Dropdown      | Yazıcı & Tarayıcı / Kırtasiye / Ofis Mobilyası / Projeksiyon & Sunum / Diğer  |
| 3    | Marka     | Dropdown      | HP / Canon / Epson / Brother / Diğer — opsiyonel                               |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                     |
| 5    | Lokasyon  | Mevcut sistem | —                                                                               |

**Kondisyonlar:** Sıfır · Az Kullanılmış · İkinci El

---

### 8.06 — Antika & Vintage ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                     |
|------|-----------|---------------|-------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                      |
| 2    | Tip       | Dropdown      | Mobilya / Saat & Mücevher / Kıyafet & Aksesuar / Porselen & Cam / Tablo & Sanat / Diğer |
| 3    | Dönem     | Serbest metin | Opsiyonel (örn. 1920'ler, Osmanlı dönemi)                                                |
| 4    | Kondisyon | Dropdown      | Aşağıya bak                                                                               |
| 5    | Lokasyon  | Mevcut sistem | —                                                                                         |

**Kondisyonlar:** Az Kullanılmış · İkinci El *(Sıfır yok — antika tanımı gereği)*

---

### 8.07 — Yiyecek & Tarım Ürünleri ✅

**Alanlar:**

| Sıra | Alan      | Tip           | Detay                                                                                             |
|------|-----------|---------------|---------------------------------------------------------------------------------------------------|
| 1    | Title     | Serbest metin | Kullanıcı elle girer                                                                              |
| 2    | Tip       | Dropdown      | Bal & Reçel / Zeytinyağı & Zeytin / Kuruyemiş & Baharat / Sebze & Meyve / Tahıl & Bakliyat / Diğer |
| 3    | Miktar    | Serbest metin | Opsiyonel (örn. 5 kg, 1 litre)                                                                   |
| 4    | Lokasyon  | Mevcut sistem | —                                                                                                 |

*(Kondisyon alanı yok — gıdada anlamsız)*

---

## Alan Validasyon Kuralları

> Bu kurallar DB kolon tipleri, Pydantic validatorlar ve Flutter input formatter'lar için referans kaynaktır.

### Genel Kural (Tüm Alanlar)
- Baş/son boşluk trim edilir
- HTML/script içeriği yasak
- Negatif değer yok
- Boşluk ile başlayamaz/bitemez

---

### Grup A — Genel Metin

| Alan | Min | Max | İzin Verilen Karakterler |
|------|-----|-----|--------------------------|
| Title | 5 | 100 | TR harf, rakam, boşluk, `. , & - ' ( )` |
| Kitap İsmi | 1 | 150 | TR harf, rakam, boşluk, tüm noktalama |
| Yazar | 2 | 80 | TR harf, boşluk, `-` `.` |
| Model (serbest) | 1 | 60 | TR harf, rakam, boşluk, `-` |
| Dönem | 0 | 50 | TR harf, rakam, boşluk, `'` `-` |
| Miktar | 0 | 30 | TR harf, rakam, boşluk |

---

### Grup B — Formatlı Tam Sayı

| Alan | Ham Rakam Max | Görünüm Formatı | Min Değer | Notlar |
|------|--------------|-----------------|-----------|--------|
| Kilometre | 7 | `1.000.000` | 0 | Binlik ayırıcı nokta; opsiyonel |
| Çalışma Saati | 5 | `10.000` | 0 | Binlik ayırıcı nokta; opsiyonel |

---

### Grup C — Alan (m²)

| Alan | Max Rakam | Max Değer | Notlar |
|------|-----------|-----------|--------|
| Brüt m² (Daire, Müstakil, İş Yeri) | 5 | 99.999 | Zorunlu |
| Net m² | 5 | 99.999 | Opsiyonel; Brüt'ten büyük olamaz |
| Arsa m² (Müstakil) | 7 | 9.999.999 | Opsiyonel |
| m² (Arsa alt kategori) | 7 | 9.999.999 | Zorunlu |
| m² (Tarla & Bahçe) | 9 | 999.999.999 | Zorunlu |
| Brüt m² (Depo & Fabrika, Bina) | 7 | 9.999.999 | Zorunlu |

---

### Grup D — Ondalıklı Sayı

| Alan | Regex Formatı | Kural |
|------|---------------|-------|
| Uzunluk (Tekne) | `[0-9]{1,3}(\.[0-9]{1,2})?` | Nokta ile başlayamaz; noktadan önce max 3, sonra max 2 rakam |

---

### Grup E — Tam Sayı

| Alan | Min | Max | Max Rakam | Notlar |
|------|-----|-----|-----------|--------|
| Kat | 0 | 200 | 3 | 0 = Zemin |
| Kat Sayısı (Bina) | 1 | 99 | 2 | — |
| Daire Sayısı (Bina) | 1 | 9999 | 4 | Opsiyonel |

---

## Notlar

- Beyaz Eşya Elektronik altında kalıyor (elektrikli cihaz mantığı)
- "Yenilenmiş" kondisyonu şimdilik yalnızca Cep Telefonu'nda; ileride Laptop/Tablet'e açılabilir
- Renk alanı şimdilik yalnızca Apple markalı telefonlarda gösterilecek (conditional field)
- Marka/Model seed seti araştırılacak: öncelik Cep Telefonu + Otomobil
- **Lokasyon sistemi:** Tüm kategorilerde "Mevcut sistem" (tek il dropdown) → İl → İlçe zincirleme dropdown'a taşınacak. Backend `/cities` endpoint yeniden yapılandırılacak, DB `location` alanı `province + district` olacak, Flutter'da iki zincirleme dropdown. İmplementasyon kategoriler tamamlandıktan sonra yapılacak.
