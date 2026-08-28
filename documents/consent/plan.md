# Kişisel Veri Rızası — Uygulama Planı

## 1. Amaç ve Kapsam

teqlif'in altyapısı ABD'de, Virginia (US-EAST-VA) bölgesinde konumlanan VPS sunucuları üzerinde çalışmaktadır. Türkiye'den kayıt olan kullanıcıların kişisel verileri bu sunuculara aktarılmaktadır. Bu durum, 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) Madde 9 kapsamında "yurt dışına kişisel veri aktarımı" sayılmakta ve hukuki bir dayanak gerektirmektedir.

**Hedef:** Kayıt ekranına, kullanıcının yurt dışı veri aktarımını anlayıp kabul ettiğini belgeleyen bir rıza akışı eklemek.

---

## 2. KVKK Hukuki Dayanak

### Temel Maddeler

| Madde | Konu | Gereksinim |
|-------|------|-----------|
| Madde 3/a | Açık rıza tanımı | Belirli konuya ilişkin, bilgilendirilmeye dayanan, özgür iradeyle açıklanan rıza |
| Madde 5 | İşlenme şartları | Rıza hizmetin ön koşulu yapılamaz (özgür irade şartı) |
| Madde 9/6/a | Açık rıza yoluyla yurt dışı aktarım | Muhtemel riskler bildirilmek kaydıyla açık rıza → **mevcut birincil mekanizma** |
| Madde 9/4/c | Uygun güvence (standart sözleşme) | Kurul'un standart sözleşmesi → **hedeflenen kalıcı mekanizma** |
| Madde 10 | Aydınlatma yükümlülüğü | Veri sorumlusu, amaç, alıcılar, hukuki sebep, kullanıcı hakları bildirilmeli |
| Madde 11 | İlgili kişi hakları | Rızayı geri alma hakkı dahil, tüm haklar erişilebilir olmalı |

### Uygulanan Strateji: Önce Rıza, Sonra Sözleşme

**Aşama 1 — Şu an uygulanacak (Madde 9/6/a + Madde 10):**
Kayıt ekranında kullanıcıya aydınlatma metni sunulur ve yurt dışı aktarıma ilişkin açık rıza checkbox'ı gösterilir. KVKK Madde 9/6/a, muhtemel riskler bildirilmek kaydıyla kullanıcı rızasını bağımsız ve geçerli bir hukuki dayanak olarak tanımlar. Checkbox doğru kurgulandığında tek başına hukuki geçerliliği vardır.

> **Önemli kısıt:** Madde 9/6/a "arızi olmak kaydıyla" ifadesini taşır. Bu yolun tüm kullanıcılar için sürekli mekanizma olarak kullanılması Kurul önünde savunulması daha güç bir pozisyon oluşturur. Risk kabul edilebilir düzeyde, ancak aşağıdaki Aşama 2 ile pekiştirilmesi önerilir.

**Aşama 2 — İdari süreçte yapılacak (Madde 9/4/c):**
Bulut sağlayıcı OVH ile KVKK Kurulu'nun standart sözleşme şablonu imzalanır. Bu işlem kullanıcı rızasını ortadan kaldırmaz; mevcut checkpoint'i güçlendirir ve "arızi kullanım" riskini tamamen bertaraf eder. Sözleşme imzasından itibaren 5 iş günü içinde Kuruma bildirim yapılması zorunludur.

**Sunucu Konumu:** Virginia, ABD (US-EAST-VA) — VPS (OVH). Tüm kullanıcı verileri bu lokasyonda depolanmaktadır. Başka bir lokasyonda yedek veya ikincil sunucu bulunmamaktadır.

---

## 3. Yapılacaklar

### 3.1 Veritabanı

`users` tablosuna aşağıdaki kolonlar eklenir (Alembic migration):

```sql
cross_border_consent_given    BOOLEAN   DEFAULT FALSE NOT NULL
cross_border_consent_at       TIMESTAMPTZ
cross_border_consent_version  VARCHAR(10)   -- rıza metninin versiyonu, örn. "v1"
cross_border_consent_revoked_at TIMESTAMPTZ
```

Rıza metni değiştiğinde versiyon arttırılır ve eski rızalar geçersiz sayılarak kullanıcıdan yeniden alınır.

### 3.2 Backend (FastAPI)

#### Yeni / Güncellenen Endpointler

| Method | Path | Açıklama |
|--------|------|---------|
| POST | `/api/auth/register` | `cross_border_consent` alanı payload'a eklenir |
| PATCH | `/api/users/me/consent` | Rızayı güncelleme (verme veya geri alma) |
| GET | `/api/users/me/consent` | Mevcut rıza durumunu getirme |

#### İş Kuralları
- Kayıt sırasında `cross_border_consent: false` ile kayıt kabul edilir (zorunlu değil).
- Kullanıcı sonradan Ayarlar ekranından rızayı verebilir veya geri alabilir.
- Rıza geri alındığında `cross_border_consent_revoked_at` doldurulur, `cross_border_consent_given` false yapılır.
- Her rıza değişikliği audit log'a yazılır.

### 3.3 Mobile (Flutter)

#### Kayıt Ekranı (signup_screen.dart)
- Mevcut checkbox'ların altına iki yeni alan eklenir:
  1. **"Kişisel Verilerimin İşlenmesi" linki** → aydınlatma metni modalı açar (Madde 10 yükümlülüğü)
  2. **Yurt dışı aktarım checkbox'ı** → açık rıza (Madde 9/6/a)

- Checkbox metni: ARB'den okunur (`consentCrossBorderTitle`)
- Checkbox zorunlu değil; işaretlenmeden kayıt tamamlanabilir
- Checkbox işaretlendiğinde kısa risk özeti gösterilir (expandable)

#### Aydınlatma Metni Modalı
- Kayıt ekranı ve Ayarlar ekranından açılabilir
- Madde 10 gereklerini karşılar:
  - Veri sorumlusu kimliği (teqlif / şirket adı)
  - İşleme amacı
  - Yurt dışı aktarım bilgisi (ABD, hizmet sunumu amacıyla)
  - Kullanıcı hakları (Madde 11 listesi)
  - İletişim / başvuru adresi

#### Ayarlar Ekranı
- "Gizlilik ve Verilerim" bölümüne yeni bir tile eklenir
- Mevcut rıza durumu gösterilir
- Rızayı geri alma veya verme imkânı sunulur
- Rıza geri alındığında kullanıcıya ne olacağı açıklanır (veri teknik olarak Virginia sunucularında kalmaya devam eder; hesap silinmediği sürece bu kaçınılmazdır)

### 3.4 Localization (ARB)

Dört dilde (`app_tr.arb`, `app_en.arb`, `app_ru.arb`, `app_ar.arb`) aşağıdaki key'ler eklenir:

| Key | Açıklama |
|-----|---------|
| `consentCrossBorderTitle` | Checkbox başlığı |
| `consentCrossBorderDesc` | Expandable risk özeti |
| `consentCrossBorderRiskNote` | ABD yeterlilik kararı olmadığı notu |
| `consentPrivacyNoticeTitle` | Aydınlatma metni modal başlığı |
| `consentPrivacyNoticeBody` | Aydınlatma metninin tamamı |
| `consentRevokeTitle` | Rızayı geri al |
| `consentRevokeConfirm` | Geri alma onay mesajı |
| `consentStatusActive` | "Rıza verildi — {date}" |
| `consentStatusNone` | "Rıza verilmedi" |

---

## 4. Rıza Metni Taslağı (Türkçe)

### Checkbox Etiketi
> Kişisel verilerimin hizmetin sunulması amacıyla Türkiye dışındaki sunuculara (ABD) aktarıldığını ve ABD'nin KVKK kapsamında yeterlilik kararına sahip olmadığını okudum, anladım.

### Expandable Risk Özeti
> ABD, Kişisel Verileri Koruma Kurulu tarafından yeterli koruma düzeyine sahip ülkeler listesinde yer almamaktadır. Bu nedenle verileriniz, Türkiye'deki düzenlemenin sağladığı güvencenin birebir karşılığıyla korunmayamayabilir. teqlif bu aktarımı yalnızca hizmetin sunulabilmesi amacıyla gerçekleştirmekte olup verilerinizi üçüncü taraflarla paylaşmamaktadır.

### Aydınlatma Metni (Madde 10 özeti)
> **Veri Sorumlusu:** [Şirket Adı / Ticaret Unvanı], [Adres]
>
> **İşleme Amacı:** Hesap oluşturma, platform hizmetlerinin sunulması, güvenlik ve doğrulama işlemleri.
>
> **Yurt Dışı Aktarım:** Hizmetlerimiz ABD'de, Virginia eyaletinde (US-EAST-VA) konumlanan sunucular üzerinde çalışmaktadır. Kişisel verileriniz bu sunuculara aktarılmaktadır.
>
> **Haklarınız (KVKK Madde 11):** Verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, düzeltme, silme ve itiraz etme haklarına sahipsiniz. Başvuru için: [e-posta adresi]

---

## 5. Uygulama Sırası

#### Teknik (Aşama 1)
1. [ ] Alembic migration — `users` tablosu kolon eklemeleri
2. [ ] Backend — `/api/users/me/consent` endpointleri
3. [ ] Backend — kayıt endpointine `cross_border_consent` alanı eklenmesi
4. [ ] ARB — dört dilde key eklenmesi + `sync_translations.py`
5. [ ] Mobile — aydınlatma metni modalı (ConsentNoticeModal widget)
6. [ ] Mobile — kayıt ekranına checkbox ve modal entegrasyonu
7. [ ] Mobile — Ayarlar ekranına rıza yönetimi tile'ı
8. [ ] Test — rıza verme, geri alma, versiyon güncellemesi senaryoları

#### İdari (Aşama 2 — teknik tamamlandıktan sonra)
9. [ ] OVH ile KVKK standart sözleşme şablonu imzalanması (Kurul'un yayımladığı şablon kullanılır)
10. [ ] Sözleşme imzasından itibaren 5 iş günü içinde KVKK Kurumu'na bildirim
11. [ ] VERBIS kaydı güncellenmesi (yurt dışı aktarım: OVH / Virginia, ABD)

---

## 6. Kapsam Dışı (Bu Plan)

- Kullanıcı verilerini fiziksel olarak Türkiye'de tutma (farklı altyapı kararı gerektirir)
- GDPR uyumluluğu (ayrı plan gerektirir)
- Çerez/cookie politikası (web için ayrı konu)
