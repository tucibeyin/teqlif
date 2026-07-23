"""
Listing description generation için kategori × kondisyon şablon sistemi.

İki katmanlı yapı:
  _FEW_SHOT   — tarz ve ton referansı; sistem promptuna girer
  _COMBO_HINT — o kombinasyon için tipik ürün detay örnekleri; LLM'e ilham
                vermek için user mesajına girer (direktif değil, fikir)
"""
from __future__ import annotations

import random


class ListingTemplates:
    # ── Tarz/ton few-shot örnekler ────────────────────────────────────────────
    # (ex1, ex2): sistem promptunda stil referansı olarak kullanılır.
    _FEW_SHOT: dict[tuple[str, str], tuple[str, str]] = {
        # ELEKTRONİK ──────────────────────────────────────────────────────────
        ("electronics", "new"): (
            "Hiç açmadım, orijinal kutusunda ve naylonunda duruyor. Garanti süresi başlamadı, tüm aksesuarları kutusunda tam.",
            "Hediye almıştım ama ihtiyacım olmadı. Kutuyu bile açmadım.",
        ),
        ("electronics", "like_new"): (
            "3 ay kullandım, cam koruyucu ve kılıfla taşıdım. Ekranında en ufak çizik yok, bataryası hâlâ çok sağlıklı.",
            "Farklı bir modele geçtiğim için satıyorum. Kutusu ve şarj adaptörüyle birlikte.",
        ),
        ("electronics", "used"): (
            "İki yıl kullandım, sağ üst köşede hafif çizik var ama ekran tertemiz. Bataryası sabah tam doluyor, gece yatarken hâlâ %30'da.",
            "Yeni telefon aldığım için satıyorum. Çizikler fiyata yansıdı.",
        ),
        ("electronics", "damaged"): (
            "Ekran sol alt köşeden kırık ama dokunmatik çalışıyor, kör nokta yok. Kamera, hoparlör ve tüm tuşlar sorunsuz.",
            "Parça veya ekran değişimi için değerlendirilebilir. Her şeyi olduğu gibi söylüyorum.",
        ),
        # VASITA ──────────────────────────────────────────────────────────────
        ("vehicles", "new"): (
            "0 km, tescil yaptırmadım, fabrika garantisi başlamadı. Tüm belgeler, iki anahtar ve servis kitapçığı eksiksiz.",
            "Depolama amaçlı almıştım, ihtiyacım kalmadı. Anahtar teslim satıyorum.",
        ),
        ("vehicles", "like_new"): (
            "2022 model, 18.000 km'de, tek sahibim. Yetkili serviste bakımlı, tramer kaydı yok, muayenesi bu yıl yenilendi.",
            "İhtiyaçtan satıyorum. Tüm belgeler mevcut, gösterime açığım.",
        ),
        ("vehicles", "used"): (
            "2018 model, 112.000 km. Motor ve şanzıman sağlam, yağ-su tüketimi yok. Sağ arka çamurlukta lokal boya var.",
            "Yeni araç alacağım için satıyorum. Bakım geçmişini gösterebilirim.",
        ),
        ("vehicles", "damaged"): (
            "Ön sağ kaporta hasarlı, motor çalışıyor fakat klima gaz istiyor. Şanzıman ve direksiyon sorunsuz.",
            "Tamir edecek veya parça için değerlendirmek isteyene uygun. Hasarı olduğu gibi söylüyorum.",
        ),
        # EMLAK ───────────────────────────────────────────────────────────────
        ("real_estate", "new"): (
            "2024 yapımı, hiç oturulmadı, anahtar teslim. 3+1, 115 m², A enerji sınıfı, kombi doğalgaz, asansörlü bina.",
            "Yatırım amaçlı aldım, ihtiyacım kalmadı. Tapu hazır, hemen taşınılabilir.",
        ),
        ("real_estate", "like_new"): (
            "2020 yapımı bina, 2+1, 80 m², 3. kat. Temiz kullandık, tadilatsız taşınılabilir. Kombi yeni, çift banyo.",
            "Şehir dışına taşındığımız için satıyoruz. Krediye uygun, tapu eksiksiz.",
        ),
        ("real_estate", "used"): (
            "15 yıllık bina, 3+1, 110 m². Mutfak yenilenmiş, elektrik tesisatı değişmiş. Banyolar kullanılabilir.",
            "İhtiyaçtan satılık. Fiyatı kalan tadilat ihtiyacına göre düşük tuttum.",
        ),
        ("real_estate", "damaged"): (
            "Depremden hafif etkilenmiş, zemin kat, 2+1. Hasar tespit raporu var, tapu temiz. Arsası değerli.",
            "Yeniden yapıma veya güçlendirmeye uygun. Fiyatı buna göre belirledim.",
        ),
        # GİYİM ───────────────────────────────────────────────────────────────
        ("fashion", "new"): (
            "Hiç giymeden satıyorum, etiketi üzerinde. Marka ürün, beden L, renk fotoğraflarda görüldüğü gibi.",
            "Hediye almıştım ama bedenim uymadı. Alıcısına hayırlı olsun.",
        ),
        ("fashion", "like_new"): (
            "1-2 kere giydim, hassas yıkamadan geçti, tertemiz. Leke, yırtık veya solma yok, sıfır gibi duruyor.",
            "Bedenim değişti, bu yüzden satıyorum.",
        ),
        ("fashion", "used"): (
            "Birkaç sezon giydim, temiz kullandım. Hafif solma var ama yırtık ya da leke yok.",
            "Gardırop yenilemesi yapıyorum, ihtiyaçtan satıyorum. Fiyata yansıttım.",
        ),
        ("fashion", "damaged"): (
            "Sağ omuzunda 1 cm yırtık var, dikişle kolayca kapanır. Leke yok, kumaş ve renk sağlam.",
            "Hasarını söyledim, fiyatı buna göre düşük tutuyorum.",
        ),
        # EV EŞYALARI ─────────────────────────────────────────────────────────
        ("home", "new"): (
            "Hiç kullanmadım, ambalajından çıkmadı. Tüm parçaları tam, garanti belgesi ve fişi mevcut.",
            "Taşınırken aldım ama o odaya sığmadı. İhtiyaç fazlası.",
        ),
        ("home", "like_new"): (
            "4-5 kez kullandım, yüzeyde en ufak çizik yok. Tüm mekanizmaları sorunsuz çalışıyor.",
            "Ev düzenlemesi değişti, bu parçaya yer kalmadı.",
        ),
        ("home", "used"): (
            "İki yıl kullandım, çalışması tam. Yüzeyde küçük çizikler var ama işlevselliği etkilemiyor.",
            "Taşınma nedeniyle satıyorum. Masraf çıkarmaz.",
        ),
        ("home", "damaged"): (
            "Çalışıyor ama alt sol köşe kırık, takviye yapılabilir. İşlevselliği etkilemiyor, görsel kusur.",
            "Hasarını söyledim, fiyatı buna göre düşük tutuyorum.",
        ),
        # SPOR ────────────────────────────────────────────────────────────────
        ("sports", "new"): (
            "Hiç kullanmadım, kutusunda duruyor. Tüm aksesuarları tam, garanti süresi geçerli.",
            "Spor programına başlayamamıştım, ihtiyaç fazlası. Alıcısına hayırlı olsun.",
        ),
        ("sports", "like_new"): (
            "5-6 kez kullandım, temiz tuttum. Hasar yok, aksesuarları tam, performansı sıfır gibi.",
            "Antrenman programım değişti, buna ihtiyacım kalmadı.",
        ),
        ("sports", "used"): (
            "Bir buçuk yıl düzenli kullandım, işlevsel ama kullanım izleri var. Bakımını yaptım.",
            "Yeni ekipman aldığım için satıyorum. Masraf çıkarmaz.",
        ),
        ("sports", "damaged"): (
            "Bir parçası kırılmış, tamir edilebilir. Temel işlevi hâlâ görüyor, diğer kısımlar sorunsuz.",
            "Tamir edecek birine uygun fiyatına gider.",
        ),
        # KİTAP ───────────────────────────────────────────────────────────────
        ("books", "new"): (
            "Hiç okunmadı, kapağı ve sayfaları tertemiz. Yeni baskı kokusu bile gidiyor.",
            "Almıştım ama okuyamadım. Alıcısına iyi okumalar.",
        ),
        ("books", "like_new"): (
            "Bir kere okudum, not veya altı çizili satır yok. Kapağı çizilmemiş, sırtı sağlam, sayfalar sararmamış.",
            "Rafta yer kaplıyor, satıyorum. İyi okumalar.",
        ),
        ("books", "used"): (
            "Okunmuş, birkaç sayfada kurşun kalem notlar var. Kapağı sağlam, sayfa eksiği yok.",
            "Kitaplığımı düzenliyorum, ihtiyaçtan satıyorum.",
        ),
        ("books", "damaged"): (
            "Kapağı yırtılmış ama sayfalar tam ve okunabilir. İçerik eksiksiz.",
            "Hasarını söyledim, fiyatı düşük tutuyorum.",
        ),
        # DİĞER ───────────────────────────────────────────────────────────────
        ("other", "new"): (
            "Sıfır, hiç kullanmadım, ambalajında duruyor. Tüm parçaları tam.",
            "İhtiyaç fazlası, alıcısına hayırlı olsun.",
        ),
        ("other", "like_new"): (
            "Az kullandım, hasar veya iz yok, sıfır gibi duruyor.",
            "İhtiyacım kalmadığı için satıyorum.",
        ),
        ("other", "used"): (
            "Temiz kullandım, işlevsel. Görsel yıpranma var ama çalışması sorunsuz.",
            "İhtiyaçtan satılık. Alıcısına hayırlı olsun.",
        ),
        ("other", "damaged"): (
            "Hasarlı, olduğu gibi söylüyorum. Fotoğraflarda açıkça görünüyor.",
            "Fiyatı buna göre düşük tuttum. Tamir edecek birine gider.",
        ),
    }

    # ── Kombine detay ilham havuzu ────────────────────────────────────────────
    # LLM'e "bu kombinasyonda hangi detayları düşünmeli?" sorusuna ilham verir.
    # User mesajına "Bu tür ürünlerde genellikle şunlar konuşulur" başlığıyla girer.
    # Direktif değil, LLM'in kendi düşünce sürecine girdi sağlayan fikir kataloğu.
    _COMBO_HINT: dict[tuple[str, str], str] = {
        # ELEKTRONİK ──────────────────────────────────────────────────────────
        ("electronics", "new"): (
            "orijinal kutusunda ve naylonunda, garanti henüz başlamamış, "
            "şarj adaptörü/kulaklık gibi aksesuarlar tam, ekrana el sürülmemiş, "
            "fabrika ayarlarında, fatura veya garanti belgesi mevcut."
        ),
        ("electronics", "like_new"): (
            "2-6 ay kullanılmış, cam koruyucu ve kılıfla taşınmış, "
            "ekranda çizik yok, batarya sağlığı yüksek, kutu ve şarj adaptörü saklı, "
            "belki kamera lensi sıfır gibi, imei temiz."
        ),
        ("electronics", "used"): (
            "1-3 yıl kullanılmış, ekranda hafif çizik olabilir, "
            "batarya işlevsel ama kapasite düşmüş olabilir, kamera ve hoparlör sorunsuz, "
            "belki aksesuar eksik, küçük kasa izleri mevcut."
        ),
        ("electronics", "damaged"): (
            "ekran kırık veya çatlak, arka cam hasarlı, su hasarı görmüş, "
            "bazı tuşlar veya portlar çalışmıyor olabilir, açılıyor ama tam işlevsel değil, "
            "parça veya tamir için değerlendirilebilir."
        ),
        # VASITA ──────────────────────────────────────────────────────────────
        ("vehicles", "new"): (
            "0 km tescilsiz, fabrika garantisi başlamamış, servis kitapçığı imzalanmamış, "
            "iki anahtar ve tüm orijinal belgeler eksiksiz, renk ve donanım paketi belirli, "
            "lastikler ve akü fabrika çıkışı."
        ),
        ("vehicles", "like_new"): (
            "2021-2023 model, 10.000-30.000 km aralığı, tek veya çift sahipli, "
            "yetkili servis geçmişli, tramer ve kaza kaydı yok, muayenesi yakın tarihli, "
            "lastikler %70+ dolulukta, iç temizliği çok iyi."
        ),
        ("vehicles", "used"): (
            "2015-2019 model, 70.000-150.000 km, motor ve şanzıman sağlam, "
            "lokal boya veya küçük kaporta hasarı olabilir, bakım geçmişi mevcut, "
            "klima ve elektrikler çalışıyor, lastikler makul durumda."
        ),
        ("vehicles", "damaged"): (
            "kaporta hasarı veya airbag açılmış, motor çalışıyor ama tam kapasite değil, "
            "kazalı veya teknik arıza mevcut, hasar kaydı var, "
            "tamir veya parça olarak değerlendirilebilir, tescil belgesi tamam."
        ),
        # EMLAK ───────────────────────────────────────────────────────────────
        ("real_estate", "new"): (
            "2022-2024 yapımı, hiç oturulmamış, A veya B enerji sınıfı, "
            "kombi veya merkezi ısıtma, asansörlü bina, tapu hazır, "
            "anahtar teslim veya proje aşamasında, 2+1 veya 3+1 seçenekleri."
        ),
        ("real_estate", "like_new"): (
            "3-8 yıllık bina, temiz kullanılmış, tadilat gerektirmiyor, "
            "kombi doğalgaz, belki ebeveyn banyosu veya giyinme odası, "
            "krediye uygun, tapu eksiksiz, iskan belgesi var."
        ),
        ("real_estate", "used"): (
            "10-25 yıllık bina, 80-130 m², mutfak veya banyo yenilenmiş olabilir, "
            "elektrik tesisatı değişmiş, eski pencereler veya tesisat olabilir, "
            "fiyat tadilat ihtiyacına göre ayarlı, tapu temiz."
        ),
        ("real_estate", "damaged"): (
            "deprem veya su baskından etkilenmiş, hasar tespit raporu mevcut, "
            "yapısal veya kozmetik hasar var, tapu temiz, imar durumu müsait, "
            "arsası değerli, yeniden yapıma veya güçlendirmeye uygun."
        ),
        # GİYİM ───────────────────────────────────────────────────────────────
        ("fashion", "new"): (
            "etiketi üzerinde, hiç giyilmemiş, marka ürün, "
            "belirli beden ve renk, ambalajında veya orijinal torbasında, "
            "hediye veya yanlış beden/renk nedeniyle satışta, iade süresi geçmiş."
        ),
        ("fashion", "like_new"): (
            "1-3 kez giyilmiş, hassas yıkamadan geçmiş, leke veya yırtık yok, "
            "renk solmamış, pill oluşmamış, beden değişimi veya tarz değişikliği nedeniyle satışta, "
            "kumaş şeklini korumuş."
        ),
        ("fashion", "used"): (
            "birkaç sezon kullanılmış, hafif renk solması veya pill olabilir, "
            "yırtık veya büyük leke yok, temiz bakımı yapılmış, "
            "dikişler sağlam, fiyat görsel duruma göre ayarlı."
        ),
        ("fashion", "damaged"): (
            "yırtık, leke veya kopuk düğme/kanca mevcut, hasar küçük ve tamir edilebilir, "
            "kumaş ve renk genel olarak iyi, "
            "fiyat hasara göre düşük, tamir edecek birine uygun."
        ),
        # EV EŞYALARI ─────────────────────────────────────────────────────────
        ("home", "new"): (
            "hiç kullanılmamış, ambalajında, tüm parçalar tam, "
            "garanti belgesi ve faturası var, "
            "ihtiyaç fazlası, taşınma veya yer sorunu nedeniyle satışta."
        ),
        ("home", "like_new"): (
            "3-10 kez kullanılmış, yüzeyde çizik veya hasar yok, "
            "tüm mekanizmalar çalışıyor, temizlenmiş, "
            "taşınma veya mobilya yenileme nedeniyle satışta."
        ),
        ("home", "used"): (
            "1-4 yıl kullanılmış, yüzeyde küçük çizikler veya kullanım izleri var, "
            "çalışması ve işlevi tam, taşınma nedeniyle elden çıkarılıyor, "
            "masraf çıkarmaz."
        ),
        ("home", "damaged"): (
            "bir parçası kırık veya kapı/çekmece düzgün kapanmıyor, "
            "yüzeyde belirgin hasar var, temel işlev hâlâ çalışıyor, "
            "tamir edilebilir veya parça olarak değerlendirilebilir."
        ),
        # SPOR ────────────────────────────────────────────────────────────────
        ("sports", "new"): (
            "hiç kullanılmamış, etiketli veya kutusunda, tüm aksesuarlar tam, "
            "garanti geçerli, spor yapmaya başlayamamak, "
            "hediye veya program değişikliği nedeniyle satışta."
        ),
        ("sports", "like_new"): (
            "3-10 kez kullanılmış, temiz tutulmuş, hasar veya yıpranma yok, "
            "aksesuarları tam, performansı sıfır gibi, "
            "program değişikliği veya farklı spor dalı nedeniyle satışta."
        ),
        ("sports", "used"): (
            "düzenli kullanılmış, görsel yıpranma izleri var, "
            "temel işlev ve performans sorunsuz, bakımı yapılmış, "
            "yeni ekipman alındığı için satışta."
        ),
        ("sports", "damaged"): (
            "bir parçası kırık veya yırtık, tamir edilebilir nitelikte, "
            "temel işlev kısmen çalışıyor, "
            "parça olarak da değerlendirilebilir, fiyat hasara göre düşük."
        ),
        # KİTAP ───────────────────────────────────────────────────────────────
        ("books", "new"): (
            "hiç okunmamış, kapak ve sayfalar tertemiz, yeni baskı kokusu var, "
            "not veya işaret yok, çift alındığı veya okuyamama nedeniyle satışta, "
            "belki özel baskı veya ciltli."
        ),
        ("books", "like_new"): (
            "bir kez okunmuş, not veya altı çizili satır yok, "
            "kapak çizilmemiş, sırt sağlam, sayfalar sararmamış, "
            "rafta yer kaplıyor veya koleksiyon daraltma nedeniyle satışta."
        ),
        ("books", "used"): (
            "birden fazla okunmuş, bazı sayfalarda kalem notu olabilir, "
            "kapak hafif eskimiş veya çizilmiş, sayfa eksiği yok, "
            "içerik ve bilgi eksiksiz, ders veya okuma amacıyla kullanılmış."
        ),
        ("books", "damaged"): (
            "kapak yırtılmış veya kopmuş, su hasarı görmüş olabilir, "
            "sırtı ayrılmış veya sayfalar dağılıyor, "
            "sayfalar büyük ölçüde tam ve okunabilir, içerik erişilebilir."
        ),
        # DİĞER ───────────────────────────────────────────────────────────────
        ("other", "new"): (
            "ambalajında veya kutusunda, tüm parçalar eksiksiz, hiç kullanılmamış, "
            "ihtiyaç fazlası veya hediye nedeniyle satışta."
        ),
        ("other", "like_new"): (
            "çok az kullanılmış, görsel iz veya hasar yok, işlevsel durumda, "
            "gerçekçi bir satış gerekçesi var."
        ),
        ("other", "used"): (
            "belirli süre kullanılmış, görsel yıpranma mevcut, işlevselliği tam, "
            "satış gerekçesi ihtiyaç değişikliği veya yenileme."
        ),
        ("other", "damaged"): (
            "belirli bir hasar mevcut, işlev kısmen etkilenmiş, "
            "tamir veya parça için değerlendirilebilir, fiyat hasara göre düşük."
        ),
    }

    @classmethod
    def get_few_shot(cls, cat: str, cond: str) -> tuple[str, str]:
        key = (cat, cond)
        return (
            cls._FEW_SHOT.get(key)
            or cls._FEW_SHOT.get(("other", cond))
            or cls._FEW_SHOT[("other", "used")]
        )

    @classmethod
    def get_combo_hint(cls, cat: str, cond: str) -> str:
        key = (cat, cond)
        return (
            cls._COMBO_HINT.get(key)
            or cls._COMBO_HINT.get(("other", cond))
            or cls._COMBO_HINT[("other", "used")]
        )
