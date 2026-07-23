"""Schema-Driven UI: category_fields + field_options tables with full seed

Revision ID: zw_category_fields_schema
Revises: zv_rename_telefon_subcategory
Create Date: 2026-07-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "zw_category_fields_schema"
down_revision: Union[str, Sequence[str], None] = "zv_rename_telefon_subcategory"
branch_labels = None
depends_on = None

# ── Seed data ─────────────────────────────────────────────────────────────────
# Each entry: (key, label_key, type, required, position, unit, depends_on)
# type: 'text' | 'number' | 'dropdown'

_FIELDS: dict[str, list[tuple]] = {
    # ── Vasıta ────────────────────────────────────────────────────────────────
    "otomobil": [
        ("marka",     "extraField_marka",     "dropdown", True,  0, None, None),
        ("model",     "extraField_model",     "dropdown", True,  1, None, "marka"),
        ("yil",       "extraField_yil",       "number",   True,  2, None, None),
        ("km",        "extraField_km",        "number",   False, 3, "km", None),
        ("yakit",     "extraField_yakit",     "dropdown", True,  4, None, None),
        ("vites",     "extraField_vites",     "dropdown", True,  5, None, None),
        ("kasa_tipi", "extraField_kasa_tipi", "dropdown", True,  6, None, None),
        ("renk",      "extraField_renk",      "dropdown", False, 7, None, None),
        ("hasar",     "extraField_hasar",     "dropdown", False, 8, None, None),
    ],
    "motosiklet": [
        ("marka",     "extraField_marka",     "dropdown", True,  0, None,   None),
        ("tip",       "extraField_tip",       "dropdown", True,  1, None,   None),
        ("model",     "extraField_model",     "dropdown", True,  2, None,   "marka"),
        ("yil",       "extraField_yil",       "number",   True,  3, None,   None),
        ("km",        "extraField_km",        "number",   False, 4, "km",   None),
        ("motor_cc",  "extraField_motor_cc",  "number",   False, 5, "cc",   None),
    ],
    "elektrikli_arac": [
        ("marka",     "extraField_marka",    "dropdown", True,  0, None,  None),
        ("model",     "extraField_model",    "dropdown", True,  1, None,  "marka"),
        ("yil",       "extraField_yil",      "number",   True,  2, None,  None),
        ("km",        "extraField_km",       "number",   False, 3, "km",  None),
        ("menzil_km", "extraField_menzil",   "number",   False, 4, "km",  None),
        ("renk",      "extraField_renk",     "dropdown", False, 5, None,  None),
    ],
    "kamyonet_minibus": [
        ("marka", "extraField_marka", "dropdown", True,  0, None, None),
        ("model", "extraField_model", "dropdown", True,  1, None, "marka"),
        ("yil",   "extraField_yil",   "number",   True,  2, None, None),
        ("km",    "extraField_km",    "number",   False, 3, "km", None),
        ("yakit", "extraField_yakit", "dropdown", True,  4, None, None),
        ("vites", "extraField_vites", "dropdown", True,  5, None, None),
    ],
    "kamyon_tir": [
        ("marka", "extraField_marka", "dropdown", True,  0, None, None),
        ("model", "extraField_model", "dropdown", True,  1, None, "marka"),
        ("yil",   "extraField_yil",   "number",   True,  2, None, None),
        ("km",    "extraField_km",    "number",   False, 3, "km", None),
        ("yakit", "extraField_yakit", "dropdown", True,  4, None, None),
        ("vites", "extraField_vites", "dropdown", True,  5, None, None),
    ],
    "traktor": [
        ("marka",          "extraField_marka",          "dropdown", True,  0, None,    None),
        ("model",          "extraField_model",          "dropdown", True,  1, None,    "marka"),
        ("yil",            "extraField_yil",            "number",   True,  2, None,    None),
        ("km",             "extraField_km",             "number",   False, 3, "km",    None),
        ("calisma_saati",  "extraField_calisma_saati",  "number",   False, 4, "saat",  None),
    ],
    "tekne_su_araci": [
        ("tip",      "extraField_tip",     "dropdown", True,  0, None, None),
        ("marka",    "extraField_marka",   "text",     False, 1, None, None),
        ("model",    "extraField_model",   "text",     False, 2, None, None),
        ("uzunluk",  "extraField_uzunluk", "text",     True,  3, "m",  None),
        ("yil",      "extraField_yil",     "number",   False, 4, None, None),
        ("yakit",    "extraField_yakit",   "dropdown", False, 5, None, None),
    ],
    "karavan": [
        ("marka", "extraField_marka", "text",   False, 0, None, None),
        ("model", "extraField_model", "text",   False, 1, None, None),
        ("yil",   "extraField_yil",   "number", False, 2, None, None),
        ("km",    "extraField_km",    "number", False, 3, "km", None),
    ],
    "yedek_parca": [
        ("marka",        "extraField_marka",        "dropdown", True,  0, None, None),
        ("uyumlu_model", "extraField_uyumlu_model", "text",     False, 1, None, None),
        ("parca_tipi",   "extraField_parca_tipi",   "text",     False, 2, None, None),
    ],
    # ── Elektronik ────────────────────────────────────────────────────────────
    "cep_telefonu": [
        ("marka",     "extraField_marka",    "dropdown", True,  0, None, None),
        ("model",     "extraField_model",    "dropdown", True,  1, None, "marka"),
        ("depolama",  "extraField_depolama", "dropdown", True,  2, None, None),
        ("ram",       "extraField_ram",      "dropdown", False, 3, None, None),
        ("renk",      "extraField_renk",     "dropdown", False, 4, None, None),
    ],
    "bilgisayar_laptop": [
        ("marka",        "extraField_marka",        "dropdown", True,  0, None, None),
        ("model",        "extraField_model",        "dropdown", False, 1, None, "marka"),
        ("islemci",      "extraField_islemci",      "dropdown", True,  2, None, None),
        ("ram",          "extraField_ram",          "dropdown", True,  3, None, None),
        ("depolama",     "extraField_depolama",     "dropdown", True,  4, None, None),
        ("ekran_boyutu", "extraField_ekran_boyutu", "dropdown", False, 5, None, None),
    ],
    "tablet": [
        ("marka",    "extraField_marka",    "dropdown", True,  0, None, None),
        ("model",    "extraField_model",    "dropdown", True,  1, None, "marka"),
        ("depolama", "extraField_depolama", "dropdown", True,  2, None, None),
        ("ram",      "extraField_ram",      "dropdown", False, 3, None, None),
    ],
    "tv_monitor": [
        ("marka",        "extraField_marka",        "text",    True,  0, None, None),
        ("model",        "extraField_model",        "text",    False, 1, None, None),
        ("ekran_boyutu", "extraField_ekran_boyutu", "dropdown",True,  2, None, None),
    ],
    "kamera": [
        ("marka", "extraField_marka", "dropdown", True,  0, None, None),
        ("tip",   "extraField_tip",   "dropdown", True,  1, None, None),
        ("model", "extraField_model", "text",     False, 2, None, None),
    ],
    "ses_sistemi": [
        ("marka", "extraField_marka", "text", True,  0, None, None),
        ("model", "extraField_model", "text", False, 1, None, None),
    ],
    "akilli_saat_bileklik": [
        ("marka", "extraField_marka", "text", True,  0, None, None),
        ("model", "extraField_model", "text", False, 1, None, None),
    ],
    "oyun_konsol": [
        ("marka", "extraField_marka", "dropdown", True, 0, None, None),
        ("model", "extraField_model", "dropdown", True, 1, None, None),
    ],
    # ── Emlak ─────────────────────────────────────────────────────────────────
    "daire": [
        ("oda_sayisi",  "extraField_oda_sayisi",  "dropdown", True,  0, None,  None),
        ("brut_m2",     "extraField_brut_m2",     "number",   True,  1, "m²",  None),
        ("net_m2",      "extraField_net_m2",      "number",   False, 2, "m²",  None),
        ("bina_yasi",   "extraField_bina_yasi",   "dropdown", False, 3, None,  None),
        ("kat",         "extraField_kat",         "number",   False, 4, None,  None),
        ("kat_sayisi",  "extraField_kat_sayisi",  "number",   False, 5, None,  None),
        ("isitma",      "extraField_isitma",      "dropdown", False, 6, None,  None),
        ("esya_durumu", "extraField_esya_durumu", "dropdown", True,  7, None,  None),
        ("asansor",     "extraField_asansor",     "dropdown", False, 8, None,  None),
        ("otopark",     "extraField_otopark",     "dropdown", False, 9, None,  None),
    ],
    "mustakil_ev_villa": [
        ("oda_sayisi",  "extraField_oda_sayisi",  "dropdown", True,  0, None,  None),
        ("brut_m2",     "extraField_brut_m2",     "number",   True,  1, "m²",  None),
        ("net_m2",      "extraField_net_m2",      "number",   False, 2, "m²",  None),
        ("arsa_m2",     "extraField_arsa_m2",     "number",   False, 3, "m²",  None),
        ("bina_yasi",   "extraField_bina_yasi",   "dropdown", False, 4, None,  None),
        ("isitma",      "extraField_isitma",      "dropdown", False, 5, None,  None),
        ("esya_durumu", "extraField_esya_durumu", "dropdown", True,  6, None,  None),
    ],
    "arsa": [
        ("m2",              "extraField_m2",              "number",   True,  0, "m²", None),
        ("tapu_durumu",     "extraField_tapu_durumu",     "dropdown", True,  1, None, None),
        ("kullanim_durumu", "extraField_kullanim_durumu", "dropdown", False, 2, None, None),
    ],
    "tarla_bahce": [
        ("m2",              "extraField_m2",              "number",   True,  0, "m²", None),
        ("tapu_durumu",     "extraField_tapu_durumu",     "dropdown", True,  1, None, None),
        ("kullanim_durumu", "extraField_kullanim_durumu", "dropdown", False, 2, None, None),
    ],
    "is_yeri_ofis": [
        ("brut_m2",     "extraField_brut_m2",     "number",   True,  0, "m²", None),
        ("net_m2",      "extraField_net_m2",      "number",   False, 1, "m²", None),
        ("kat",         "extraField_kat",         "number",   False, 2, None, None),
        ("isitma",      "extraField_isitma",      "dropdown", False, 3, None, None),
        ("esya_durumu", "extraField_esya_durumu", "dropdown", False, 4, None, None),
    ],
    "depo_fabrika": [
        ("brut_m2", "extraField_brut_m2", "number", True,  0, "m²", None),
        ("kat",     "extraField_kat",     "number", False, 1, None,  None),
    ],
    "bina": [
        ("kat_sayisi",   "extraField_kat_sayisi",   "number", True,  0, None,  None),
        ("daire_sayisi", "extraField_daire_sayisi", "number", True,  1, None,  None),
        ("brut_m2",      "extraField_brut_m2",      "number", False, 2, "m²",  None),
    ],
    # ── Giyim ─────────────────────────────────────────────────────────────────
    "kadin_giyim": [
        ("beden", "extraField_beden", "dropdown", True,  0, None, None),
        ("renk",  "extraField_renk",  "dropdown", False, 1, None, None),
    ],
    "erkek_giyim": [
        ("beden", "extraField_beden", "dropdown", True,  0, None, None),
        ("renk",  "extraField_renk",  "dropdown", False, 1, None, None),
    ],
    "cocuk_giyim": [
        ("beden", "extraField_beden", "dropdown", True,  0, None, None),
        ("renk",  "extraField_renk",  "dropdown", False, 1, None, None),
    ],
    "ayakkabi": [
        ("marka",  "extraField_marka",  "text",     False, 0, None, None),
        ("tip",    "extraField_tip",    "dropdown", True,  1, None, None),
        ("numara", "extraField_numara", "dropdown", True,  2, None, None),
        ("renk",   "extraField_renk",  "dropdown", False, 3, None, None),
    ],
    "canta": [
        ("marka",   "extraField_marka",   "text",     False, 0, None, None),
        ("renk",    "extraField_renk",    "dropdown", False, 1, None, None),
        ("malzeme", "extraField_malzeme", "dropdown", False, 2, None, None),
    ],
    "taki_mucevher": [
        ("malzeme",    "extraField_malzeme",    "dropdown", True,  0, None, None),
        ("altin_ayar", "extraField_altin_ayar", "dropdown", False, 1, None, None),
        ("gumus_ayar", "extraField_gumus_ayar", "dropdown", False, 2, None, None),
        ("renk",       "extraField_renk",       "dropdown", False, 3, None, None),
    ],
    "saat_giyim": [
        ("marka",    "extraField_marka",    "dropdown", True,  0, None, None),
        ("model",    "extraField_model",    "dropdown", False, 1, None, "marka"),
        ("cinsiyet", "extraField_cinsiyet", "dropdown", True,  2, None, None),
    ],
    "sapka_kemer_aksesuar": [
        ("renk", "extraField_renk", "dropdown", False, 0, None, None),
    ],
    # ── Ev & Yaşam ────────────────────────────────────────────────────────────
    "mobilya": [
        ("tip",     "extraField_tip",     "dropdown", True,  0, None, None),
        ("malzeme", "extraField_malzeme", "dropdown", False, 1, None, None),
        ("renk",    "extraField_renk",    "dropdown", False, 2, None, None),
    ],
    "ev_tekstil": [
        ("tip",  "extraField_tip",  "dropdown", True,  0, None, None),
        ("renk", "extraField_renk", "dropdown", False, 1, None, None),
    ],
    "aydinlatma": [
        ("tip",  "extraField_tip",  "dropdown", True,  0, None, None),
        ("renk", "extraField_renk", "dropdown", False, 1, None, None),
    ],
    "antika_koleksiyon": [
        ("yil", "extraField_yil", "text", False, 0, None, None),
    ],
    # ── Spor ──────────────────────────────────────────────────────────────────
    "bisiklet": [
        ("marka",       "extraField_marka",       "dropdown", True,  0, None, None),
        ("model",       "extraField_model",       "dropdown", False, 1, None, "marka"),
        ("tip",         "extraField_tip",         "dropdown", True,  2, None, None),
        ("jant_boyutu", "extraField_jant_boyutu", "dropdown", False, 3, None, None),
    ],
    "spor_aleti_fitness": [
        ("marka", "extraField_marka", "text", False, 0, None, None),
    ],
    "top_takim_sporlari": [
        ("spor_dali", "extraField_spor_dali", "dropdown", True,  0, None, None),
        ("marka",     "extraField_marka",     "text",     False, 1, None, None),
    ],
    "doga_sporlari": [
        ("spor_dali", "extraField_spor_dali", "dropdown", False, 0, None, None),
        ("marka",     "extraField_marka",     "text",     False, 1, None, None),
    ],
    # ── Kitap ─────────────────────────────────────────────────────────────────
    "roman_hikaye": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yazar",      "extraField_yazar",      "text", True,  1, None, None),
        ("yayinevi",   "extraField_yayinevi",   "text", False, 2, None, None),
    ],
    "bilim_kurgu": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yazar",      "extraField_yazar",      "text", True,  1, None, None),
        ("yayinevi",   "extraField_yayinevi",   "text", False, 2, None, None),
    ],
    "kisisel_gelisim": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yazar",      "extraField_yazar",      "text", True,  1, None, None),
        ("yayinevi",   "extraField_yayinevi",   "text", False, 2, None, None),
    ],
    "cocuk_kitaplari": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yazar",      "extraField_yazar",      "text", False, 1, None, None),
        ("yayinevi",   "extraField_yayinevi",   "text", False, 2, None, None),
    ],
    "ders_okul": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yayinevi",   "extraField_yayinevi",   "text", False, 1, None, None),
        ("yazar",      "extraField_yazar",      "text", False, 2, None, None),
    ],
    "muzik_sanat_kitap": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yazar",      "extraField_yazar",      "text", False, 1, None, None),
    ],
    "koleksiyon_dergi": [
        ("kitap_ismi", "extraField_kitap_ismi", "text", True,  0, None, None),
        ("yayinevi",   "extraField_yayinevi",   "text", False, 1, None, None),
    ],
    # ── Diğer ─────────────────────────────────────────────────────────────────
    "evcil_hayvan": [
        ("tip", "extraField_tip", "dropdown", True,  0, None, None),
        ("irk", "extraField_irk", "text",     False, 1, None, None),
    ],
    "muzik_aleti": [
        ("tip",   "extraField_tip",   "dropdown", True,  0, None, None),
        ("marka", "extraField_marka", "text",     False, 1, None, None),
    ],
    "foto_video_ekipmani": [
        ("tip",   "extraField_tip",   "dropdown", True,  0, None, None),
        ("marka", "extraField_marka", "text",     False, 1, None, None),
    ],
}

# ── Standalone option lists ────────────────────────────────────────────────────
# Reused across multiple fields; referenced by (subcategory, field_key)

_RENK = [
    ("beyaz","Beyaz"),("gri","Gri"),("siyah","Siyah"),("mavi","Mavi"),
    ("kirmizi","Kırmızı"),("yesil","Yeşil"),("sari","Sarı"),("turuncu","Turuncu"),
    ("mor","Mor"),("pembe","Pembe"),("kahverengi","Kahverengi"),("bej","Bej"),
    ("altin","Altın"),("gumus","Gümüş"),("diger","Diğer"),
]
_YAKIT = [
    ("benzin","Benzin"),("dizel","Dizel"),("lpg","LPG"),
    ("hibrit","Hibrit"),("elektrik","Elektrik"),("diger","Diğer"),
]
_VITES = [
    ("manuel","Manuel"),("otomatik","Otomatik"),
    ("yari_otomatik","Yarı Otomatik"),("cvt","CVT"),
]
_VITES_3 = [
    ("manuel","Manuel"),("otomatik","Otomatik"),("yari_otomatik","Yarı Otomatik"),
]
_KASA = [
    ("sedan","Sedan"),("hatchback","Hatchback"),("suv","SUV"),
    ("station_wagon","Station Wagon"),("coupe","Coupe"),("cabriolet","Cabriolet"),
    ("pickup","Pickup"),("van","Van"),("minibus","Minibüs"),("diger","Diğer"),
]
_HASAR = [
    ("hasarsiz","Hasarsız"),("boyali","Boyalı"),("degisen","Değişen"),("hasarli","Hasarlı"),
]
_MARKA_ARAC = [
    ("alfa_romeo","Alfa Romeo"),("audi","Audi"),("bmw","BMW"),("chevrolet","Chevrolet"),
    ("citroen","Citroën"),("dacia","Dacia"),("fiat","Fiat"),("ford","Ford"),
    ("honda","Honda"),("hyundai","Hyundai"),("jeep","Jeep"),("kia","Kia"),
    ("land_rover","Land Rover"),("mazda","Mazda"),("mercedes","Mercedes-Benz"),
    ("mitsubishi","Mitsubishi"),("nissan","Nissan"),("opel","Opel"),("peugeot","Peugeot"),
    ("porsche","Porsche"),("renault","Renault"),("seat","SEAT"),("skoda","Skoda"),
    ("subaru","Subaru"),("tesla","Tesla"),("togg","TOGG"),("toyota","Toyota"),
    ("volkswagen","Volkswagen"),("volvo","Volvo"),("diger","Diğer"),
]
_MARKA_ELEKTRIK = [
    ("tesla","Tesla"),("togg","TOGG"),("bmw","BMW"),("audi","Audi"),
    ("hyundai","Hyundai"),("kia","Kia"),("volkswagen","Volkswagen"),("nissan","Nissan"),
    ("renault","Renault"),("porsche","Porsche"),("mercedes","Mercedes-Benz"),
    ("peugeot","Peugeot"),("diger","Diğer"),
]
_MARKA_MOTO = [
    ("honda","Honda"),("yamaha","Yamaha"),("kawasaki","Kawasaki"),("suzuki","Suzuki"),
    ("bmw","BMW"),("ducati","Ducati"),("harley","Harley-Davidson"),
    ("royal_enfield","Royal Enfield"),("ktm","KTM"),("triumph","Triumph"),
    ("aprilia","Aprilia"),("diger","Diğer"),
]
_MOTO_TIP = [
    ("naked","Naked"),("sport","Sport"),("touring","Touring"),("enduro","Enduro"),
    ("scooter","Scooter"),("chopper","Chopper"),("adventure","Adventure"),("diger","Diğer"),
]
_MARKA_KAMYON = [
    ("ford","Ford"),("fiat","Fiat"),("volkswagen","Volkswagen"),("mercedes","Mercedes-Benz"),
    ("renault","Renault"),("opel","Opel"),("peugeot","Peugeot"),("isuzu","Isuzu"),
    ("iveco","Iveco"),("man","MAN"),("daf","DAF"),("volvo","Volvo"),
    ("scania","Scania"),("diger","Diğer"),
]
_MARKA_TRAKTOR = [
    ("new_holland","New Holland"),("john_deere","John Deere"),
    ("massey_ferguson","Massey Ferguson"),("kubota","Kubota"),
    ("fendt","Fendt"),("case","Case"),("tumosan","Tümosan"),("diger","Diğer"),
]
_TEKNE_TIP = [
    ("motor_tekne","Motor Tekne"),("yelkenli","Yelkenli"),("surat_teknesi","Sürat Teknesi"),
    ("kotra","Kotra"),("kanotaj","Kanotaj"),("jet_ski","Jet Ski"),("diger","Diğer"),
]
_TEKNE_YAKIT = [
    ("benzin","Benzin"),("dizel","Dizel"),("elektrik","Elektrik"),
    ("yelken","Yelken"),("diger","Diğer"),
]
_MARKA_TEL = [
    ("apple","Apple"),("samsung","Samsung"),("xiaomi","Xiaomi"),("huawei","Huawei"),
    ("oneplus","OnePlus"),("google","Google"),("oppo","Oppo"),("realme","Realme"),
    ("nokia","Nokia"),("motorola","Motorola"),("diger","Diğer"),
]
_DEPOLAMA = [
    ("16gb","16 GB"),("32gb","32 GB"),("64gb","64 GB"),("128gb","128 GB"),
    ("256gb","256 GB"),("512gb","512 GB"),("1tb","1 TB"),("2tb","2 TB"),
]
_RAM = [
    ("2gb","2 GB"),("3gb","3 GB"),("4gb","4 GB"),("6gb","6 GB"),
    ("8gb","8 GB"),("12gb","12 GB"),("16gb","16 GB"),("32gb","32 GB"),("64gb","64 GB"),
]
_MARKA_BIL = [
    ("apple","Apple"),("asus","Asus"),("lenovo","Lenovo"),("dell","Dell"),("hp","HP"),
    ("msi","MSI"),("acer","Acer"),("toshiba","Toshiba"),("samsung","Samsung"),
    ("huawei","Huawei"),("diger","Diğer"),
]
_ISLEMCI = [
    ("intel_i3","Intel Core i3"),("intel_i5","Intel Core i5"),("intel_i7","Intel Core i7"),
    ("intel_i9","Intel Core i9"),("amd_r5","AMD Ryzen 5"),("amd_r7","AMD Ryzen 7"),
    ("amd_r9","AMD Ryzen 9"),("apple_m1","Apple M1"),("apple_m2","Apple M2"),
    ("apple_m3","Apple M3"),("apple_m4","Apple M4"),("diger","Diğer"),
]
_EKRAN = [
    ("11","11\""),("13","13\""),("14","14\""),("15","15\""),("16","16\""),
    ("17","17\""),("24","24\""),("27","27\""),("32","32\""),("diger","Diğer"),
]
_KAMERA_TIP = [
    ("dslr","DSLR"),("mirrorless","Mirrorless"),("kompakt","Kompakt"),
    ("action","Action Kamera"),("video","Video Kamera"),("diger","Diğer"),
]
_MARKA_KAMERA = [
    ("canon","Canon"),("nikon","Nikon"),("sony","Sony"),("fujifilm","Fujifilm"),
    ("panasonic","Panasonic"),("olympus","Olympus"),("gopro","GoPro"),("diger","Diğer"),
]
_KONSOL_MARKA = [
    ("playstation","PlayStation"),("xbox","Xbox"),("nintendo","Nintendo"),("diger","Diğer"),
]
_KONSOL_MODEL = [
    ("ps5","PlayStation 5"),("ps4","PlayStation 4"),("ps4_pro","PlayStation 4 Pro"),
    ("xbox_series_x","Xbox Series X"),("xbox_series_s","Xbox Series S"),
    ("xbox_one","Xbox One"),("nintendo_switch","Nintendo Switch"),
    ("nintendo_switch_lite","Nintendo Switch Lite"),("diger","Diğer"),
]
_ODA = [
    ("1+0","1+0 Stüdyo"),("1+1","1+1"),("2+1","2+1"),("3+1","3+1"),
    ("4+1","4+1"),("5+1","5+1"),("6+1","6+1 ve üzeri"),
]
_BINA_YASI = [
    ("sifir","Sıfır (0)"),("1_5","1–5 yıl"),("6_10","6–10 yıl"),
    ("11_15","11–15 yıl"),("16_20","16–20 yıl"),("21_plus","21 yıl ve üzeri"),
]
_ISITMA = [
    ("kombi","Kombi"),("dogalgaz","Doğalgaz (Merkezi)"),("soba","Soba"),
    ("klima","Klima"),("yerden_isitma","Yerden Isıtma"),("yok","Yok"),
]
_ESYA = [
    ("esyali","Eşyalı"),("yari_esyali","Yarı Eşyalı"),("bos","Boş"),
]
_VAR_YOK = [("var","Var"),("yok","Yok")]
_TAPU = [
    ("kat_mulkiyeti","Kat Mülkiyeti"),("kat_irtifaki","Kat İrtifakı"),
    ("hisseli","Hisseli Tapu"),("arsa","Arsa Tapusu"),("diger","Diğer"),
]
_ARSA_KULLANIM = [
    ("konut","Konut İmarlı"),("ticari","Ticari İmarlı"),
    ("tarimsal","Tarımsal"),("sanayi","Sanayi"),("diger","Diğer"),
]
_BEDEN_K = [
    ("xxs","XXS"),("xs","XS"),("s","S"),("m","M"),("l","L"),
    ("xl","XL"),("xxl","XXL"),("xxxl","XXXL"),("4xl","4XL"),
]
_BEDEN_C = [
    ("0_3ay","0–3 Ay"),("3_6ay","3–6 Ay"),("6_12ay","6–12 Ay"),
    ("1_2yas","1–2 Yaş"),("3_4yas","3–4 Yaş"),("5_6yas","5–6 Yaş"),
    ("7_8yas","7–8 Yaş"),("9_10yas","9–10 Yaş"),("11_12yas","11–12 Yaş"),("13_14yas","13–14 Yaş"),
]
_NUMARA = [
    ("35","35"),("36","36"),("37","37"),("38","38"),("39","39"),("40","40"),
    ("41","41"),("42","42"),("43","43"),("44","44"),("45","45"),("46","46"),("47","47"),
]
_AYAK_TIP = [
    ("spor","Spor / Sneaker"),("klasik","Klasik"),("bot","Bot"),
    ("sandalet","Sandalet"),("terlik","Terlik"),("topuklu","Topuklu"),("diger","Diğer"),
]
_CANTA_MAL = [
    ("deri","Deri"),("suni_deri","Suni Deri"),("kumas","Kumaş"),
    ("kanvas","Kanvas"),("diger","Diğer"),
]
_TAKI_MAL = [
    ("altin","Altın"),("gumus","Gümüş"),("platin","Platin"),
    ("elmas","Elmas"),("dogal_tas","Doğal Taş"),("diger","Diğer"),
]
_ALTIN_AYAR = [
    ("8","8 Ayar"),("14","14 Ayar"),("18","18 Ayar"),("22","22 Ayar"),("24","24 Ayar"),
]
_GUMUS_AYAR = [
    ("925","925 Ayar (Sterlin)"),("800","800 Ayar"),("diger","Diğer"),
]
_SAAT_CIN = [("erkek","Erkek"),("kadin","Kadın"),("unisex","Unisex")]
_MARKA_SAAT = [
    ("rolex","Rolex"),("omega","Omega"),("seiko","Seiko"),("casio","Casio"),
    ("tissot","Tissot"),("tag_heuer","TAG Heuer"),("fossil","Fossil"),
    ("swatch","Swatch"),("diger","Diğer"),
]
_MOBILYA_TIP = [
    ("koltuk","Koltuk / Kanepe"),("yatak","Yatak"),("masa","Masa"),
    ("sandalye","Sandalye"),("dolap","Dolap / Gardırop"),("raf","Raf / Kitaplık"),
    ("sehpa","Sehpa"),("diger","Diğer"),
]
_MOBILYA_MAL = [
    ("ahsap","Ahşap"),("metal","Metal"),("plastik","Plastik"),
    ("cam","Cam"),("deri","Deri"),("kumas","Kumaş"),("diger","Diğer"),
]
_EV_TEKSTIL = [
    ("nevresim","Nevresim Takımı"),("yorgan","Yorgan"),("yastik","Yastık"),
    ("havlu","Havlu"),("perde","Perde"),("hali","Halı / Kilim"),("diger","Diğer"),
]
_AYDINLATMA = [
    ("avize","Avize"),("abajur","Abajur"),("masa_lambasi","Masa Lambası"),
    ("aplik","Aplik"),("ayak_lambasi","Ayak Lambası"),("diger","Diğer"),
]
_BISIKLET_TIP = [
    ("dag","Dağ Bisikleti"),("yol","Yol Bisikleti"),("sehir","Şehir Bisikleti"),
    ("bmx","BMX"),("elektrikli","Elektrikli Bisiklet"),("katlanan","Katlanan Bisiklet"),
    ("diger","Diğer"),
]
_MARKA_BIS = [
    ("giant","Giant"),("trek","Trek"),("specialized","Specialized"),("bianchi","Bianchi"),
    ("scott","Scott"),("merida","Merida"),("cannondale","Cannondale"),("diger","Diğer"),
]
_JANT = [
    ("20","20\""),("24","24\""),("26","26\""),
    ("27.5","27.5\""),("28","28\""),("29","29\""),
]
_SPOR_DALI = [
    ("futbol","Futbol"),("basketbol","Basketbol"),("voleybol","Voleybol"),
    ("tenis","Tenis"),("yuzme","Yüzme"),("kosu","Koşu"),("boks","Boks / Muay Thai"),
    ("yoga","Yoga / Pilates"),("doga_sporlari","Doğa Sporları"),("diger","Diğer"),
]
_HAYVAN = [
    ("kopek","Köpek"),("kedi","Kedi"),("kus","Kuş"),("balik","Balık"),
    ("hamster","Hamster"),("tavsan","Tavşan"),("diger","Diğer"),
]
_MUZIK_TIP = [
    ("gitar","Gitar"),("piyano","Piyano / Klavye"),("davul","Davul / Perküsyon"),
    ("keman","Keman"),("saz","Saz / Bağlama"),("flut","Flüt"),("diger","Diğer"),
]
_FOTO_TIP = [
    ("kamera","Kamera"),("lens","Lens"),("tripod","Tripod"),
    ("drone","Drone"),("flas","Flaş / Işık"),("diger","Diğer"),
]

# ── Which option list goes to which (subcategory, field_key) ──────────────────
# Value: list of (value, label) for top-level options
_TOP_OPTIONS: dict[tuple[str, str], list[tuple[str, str]]] = {
    # otomobil
    ("otomobil", "marka"):     _MARKA_ARAC,
    ("otomobil", "yakit"):     _YAKIT,
    ("otomobil", "vites"):     _VITES,
    ("otomobil", "kasa_tipi"): _KASA,
    ("otomobil", "renk"):      _RENK,
    ("otomobil", "hasar"):     _HASAR,
    # motosiklet
    ("motosiklet", "marka"): _MARKA_MOTO,
    ("motosiklet", "tip"):   _MOTO_TIP,
    # elektrikli_arac
    ("elektrikli_arac", "marka"): _MARKA_ELEKTRIK,
    ("elektrikli_arac", "renk"):  _RENK,
    # kamyonet_minibus
    ("kamyonet_minibus", "marka"): _MARKA_KAMYON,
    ("kamyonet_minibus", "yakit"): _YAKIT,
    ("kamyonet_minibus", "vites"): _VITES_3,
    # kamyon_tir
    ("kamyon_tir", "marka"): _MARKA_KAMYON,
    ("kamyon_tir", "yakit"): _YAKIT,
    ("kamyon_tir", "vites"): _VITES_3,
    # traktor
    ("traktor", "marka"): _MARKA_TRAKTOR,
    # tekne
    ("tekne_su_araci", "tip"):   _TEKNE_TIP,
    ("tekne_su_araci", "yakit"): _TEKNE_YAKIT,
    # yedek_parca
    ("yedek_parca", "marka"): _MARKA_ARAC,
    # cep_telefonu
    ("cep_telefonu", "marka"):    _MARKA_TEL,
    ("cep_telefonu", "depolama"): _DEPOLAMA,
    ("cep_telefonu", "ram"):      _RAM,
    ("cep_telefonu", "renk"):     _RENK,
    # bilgisayar
    ("bilgisayar_laptop", "marka"):        _MARKA_BIL,
    ("bilgisayar_laptop", "islemci"):      _ISLEMCI,
    ("bilgisayar_laptop", "ram"):          _RAM,
    ("bilgisayar_laptop", "depolama"):     _DEPOLAMA,
    ("bilgisayar_laptop", "ekran_boyutu"): _EKRAN,
    # tablet — marka = telefon marka listesi
    ("tablet", "marka"):    _MARKA_TEL,
    ("tablet", "depolama"): _DEPOLAMA,
    ("tablet", "ram"):      _RAM,
    # tv_monitor
    ("tv_monitor", "ekran_boyutu"): _EKRAN,
    # kamera
    ("kamera", "marka"): _MARKA_KAMERA,
    ("kamera", "tip"):   _KAMERA_TIP,
    # oyun_konsol
    ("oyun_konsol", "marka"): _KONSOL_MARKA,
    ("oyun_konsol", "model"): _KONSOL_MODEL,
    # emlak
    ("daire", "oda_sayisi"):  _ODA,
    ("daire", "bina_yasi"):   _BINA_YASI,
    ("daire", "isitma"):      _ISITMA,
    ("daire", "esya_durumu"): _ESYA,
    ("daire", "asansor"):     _VAR_YOK,
    ("daire", "otopark"):     _VAR_YOK,
    ("mustakil_ev_villa", "oda_sayisi"):  _ODA,
    ("mustakil_ev_villa", "bina_yasi"):   _BINA_YASI,
    ("mustakil_ev_villa", "isitma"):      _ISITMA,
    ("mustakil_ev_villa", "esya_durumu"): _ESYA,
    ("arsa", "tapu_durumu"):      _TAPU,
    ("arsa", "kullanim_durumu"):  _ARSA_KULLANIM,
    ("tarla_bahce", "tapu_durumu"):     _TAPU,
    ("tarla_bahce", "kullanim_durumu"): _ARSA_KULLANIM,
    ("is_yeri_ofis", "isitma"):      _ISITMA,
    ("is_yeri_ofis", "esya_durumu"): _ESYA,
    # giyim
    ("kadin_giyim", "beden"): _BEDEN_K,
    ("kadin_giyim", "renk"):  _RENK,
    ("erkek_giyim", "beden"): _BEDEN_K,
    ("erkek_giyim", "renk"):  _RENK,
    ("cocuk_giyim", "beden"): _BEDEN_C,
    ("cocuk_giyim", "renk"):  _RENK,
    ("ayakkabi", "tip"):    _AYAK_TIP,
    ("ayakkabi", "numara"): _NUMARA,
    ("ayakkabi", "renk"):   _RENK,
    ("canta", "renk"):    _RENK,
    ("canta", "malzeme"): _CANTA_MAL,
    ("taki_mucevher", "malzeme"):    _TAKI_MAL,
    ("taki_mucevher", "altin_ayar"): _ALTIN_AYAR,
    ("taki_mucevher", "gumus_ayar"): _GUMUS_AYAR,
    ("taki_mucevher", "renk"):       _RENK,
    ("saat_giyim", "marka"):    _MARKA_SAAT,
    ("saat_giyim", "cinsiyet"): _SAAT_CIN,
    ("sapka_kemer_aksesuar", "renk"): _RENK,
    # ev
    ("mobilya", "tip"):     _MOBILYA_TIP,
    ("mobilya", "malzeme"): _MOBILYA_MAL,
    ("mobilya", "renk"):    _RENK,
    ("ev_tekstil", "tip"):  _EV_TEKSTIL,
    ("ev_tekstil", "renk"): _RENK,
    ("aydinlatma", "tip"):  _AYDINLATMA,
    ("aydinlatma", "renk"): _RENK,
    # spor
    ("bisiklet", "marka"):       _MARKA_BIS,
    ("bisiklet", "tip"):         _BISIKLET_TIP,
    ("bisiklet", "jant_boyutu"): _JANT,
    ("top_takim_sporlari", "spor_dali"): _SPOR_DALI,
    ("doga_sporlari", "spor_dali"):      _SPOR_DALI,
    # diger
    ("evcil_hayvan", "tip"):      _HAYVAN,
    ("muzik_aleti", "tip"):       _MUZIK_TIP,
    ("foto_video_ekipmani", "tip"): _FOTO_TIP,
}

# ── Conditional options (brand → model) ───────────────────────────────────────
# key: (subcategory, field_key)
# value: dict[parent_option_value → list[(value, label)]]

_COND_ARAC = {
    "alfa_romeo": [("giulia","Giulia"),("stelvio","Stelvio"),("giulietta","Giulietta"),("tonale","Tonale"),("156","156")],
    "audi":       [("a3","A3"),("a4","A4"),("a6","A6"),("q3","Q3"),("q5","Q5")],
    "bmw":        [("1_serisi","1 Serisi"),("3_serisi","3 Serisi"),("5_serisi","5 Serisi"),("x3","X3"),("x5","X5")],
    "chevrolet":  [("captiva","Captiva"),("malibu","Malibu"),("cruze","Cruze"),("spark","Spark"),("orlando","Orlando")],
    "citroen":    [("c3","C3"),("c4","C4"),("c3_aircross","C3 Aircross"),("c5_aircross","C5 Aircross"),("berlingo","Berlingo")],
    "dacia":      [("duster","Duster"),("sandero","Sandero"),("logan","Logan"),("jogger","Jogger"),("spring","Spring")],
    "fiat":       [("egea","Egea"),("panda","Panda"),("500","500"),("tipo","Tipo"),("doblo","Doblò")],
    "ford":       [("focus","Focus"),("fiesta","Fiesta"),("kuga","Kuga"),("puma","Puma"),("transit_custom","Transit Custom")],
    "honda":      [("civic","Civic"),("cr_v","CR-V"),("hr_v","HR-V"),("jazz","Jazz"),("accord","Accord")],
    "hyundai":    [("i20","i20"),("i30","i30"),("tucson","Tucson"),("kona","Kona"),("santa_fe","Santa Fe")],
    "jeep":       [("renegade","Renegade"),("compass","Compass"),("wrangler","Wrangler"),("cherokee","Cherokee"),("grand_cherokee","Grand Cherokee")],
    "kia":        [("sportage","Sportage"),("ceed","Ceed"),("stonic","Stonic"),("rio","Rio"),("sorento","Sorento")],
    "land_rover": [("defender","Defender"),("discovery","Discovery"),("range_rover","Range Rover"),("discovery_sport","Discovery Sport"),("range_rover_sport","Range Rover Sport")],
    "mazda":      [("cx_5","CX-5"),("mazda3","Mazda3"),("cx_30","CX-30"),("mazda6","Mazda6"),("mx_5","MX-5")],
    "mercedes":   [("a_serisi","A Serisi"),("c_serisi","C Serisi"),("e_serisi","E Serisi"),("glc","GLC"),("gle","GLE")],
    "mitsubishi": [("outlander","Outlander"),("eclipse_cross","Eclipse Cross"),("asx","ASX"),("l200","L200"),("pajero","Pajero")],
    "nissan":     [("qashqai","Qashqai"),("juke","Juke"),("micra","Micra"),("x_trail","X-Trail"),("leaf","Leaf")],
    "opel":       [("astra","Astra"),("corsa","Corsa"),("mokka","Mokka"),("crossland","Crossland"),("grandland","Grandland")],
    "peugeot":    [("208","208"),("308","308"),("2008","2008"),("3008","3008"),("508","508")],
    "porsche":    [("911","911"),("cayenne","Cayenne"),("macan","Macan"),("panamera","Panamera"),("taycan","Taycan")],
    "renault":    [("clio","Clio"),("megane","Megane"),("duster","Duster"),("kadjar","Kadjar"),("symbol","Symbol")],
    "seat":       [("ibiza","Ibiza"),("leon","Leon"),("arona","Arona"),("ateca","Ateca"),("tarraco","Tarraco")],
    "skoda":      [("fabia","Fabia"),("octavia","Octavia"),("karoq","Karoq"),("kodiaq","Kodiaq"),("superb","Superb")],
    "subaru":     [("forester","Forester"),("outback","Outback"),("xv","XV"),("impreza","Impreza"),("legacy","Legacy")],
    "tesla":      [("model_3","Model 3"),("model_y","Model Y"),("model_s","Model S"),("model_x","Model X"),("cybertruck","Cybertruck")],
    "togg":       [("t10x","T10X"),("t10f","T10F")],
    "toyota":     [("corolla","Corolla"),("yaris","Yaris"),("yaris_cross","Yaris Cross"),("rav4","RAV4"),("c_hr","C-HR")],
    "volkswagen": [("golf","Golf"),("passat","Passat"),("polo","Polo"),("tiguan","Tiguan"),("t_roc","T-Roc")],
    "volvo":      [("xc40","XC40"),("xc60","XC60"),("xc90","XC90"),("s60","S60"),("v60","V60")],
}
_COND_ELEKTRIK = {
    "tesla":      [("model_3","Model 3"),("model_y","Model Y"),("model_s","Model S"),("model_x","Model X"),("cybertruck","Cybertruck")],
    "togg":       [("t10x","T10X"),("t10f","T10F")],
    "bmw":        [("i4","i4"),("ix","iX"),("ix1","iX1"),("i5","i5"),("i3","i3")],
    "audi":       [("q4_etron","Q4 e-tron"),("etron_gt","e-tron GT"),("q8_etron","Q8 e-tron"),("a6_etron","A6 e-tron"),("q6_etron","Q6 e-tron")],
    "hyundai":    [("ioniq5","IONIQ 5"),("ioniq6","IONIQ 6"),("kona_electric","Kona Electric"),("tucson_phev","Tucson PHEV"),("santa_fe_phev","Santa Fe PHEV")],
    "kia":        [("ev6","EV6"),("ev9","EV9"),("niro_ev","Niro EV"),("sportage_phev","Sportage PHEV"),("ev3","EV3")],
    "volkswagen": [("id4","ID.4"),("id3","ID.3"),("id7","ID.7"),("id5","ID.5"),("id_buzz","ID. Buzz")],
    "nissan":     [("leaf","Leaf"),("ariya","Ariya"),("leaf_eplus","Leaf e+"),("townstar_ev","Townstar EV"),("qashqai_epower","Qashqai e-POWER")],
    "renault":    [("megane_etech","Megane E-Tech"),("zoe","Zoe"),("twingo_electric","Twingo Electric"),("scenic_etech","Scenic E-Tech"),("5_etech","5 E-Tech")],
    "porsche":    [("taycan","Taycan"),("taycan_st","Taycan Sport Turismo"),("taycan_ct","Taycan Cross Turismo"),("cayenne_e_hybrid","Cayenne E-Hybrid"),("panamera_e_hybrid","Panamera E-Hybrid")],
    "mercedes":   [("eqa","EQA"),("eqb","EQB"),("eqc","EQC"),("eqs","EQS"),("eqe","EQE")],
    "peugeot":    [("e208","e-208"),("e2008","e-2008"),("e308","e-308"),("e3008","e-3008"),("e_expert","e-Expert")],
}
_COND_MOTO = {
    "honda":        [("cb650r","CB650R"),("cbr600rr","CBR600RR"),("cb500f","CB500F"),("africa_twin","Africa Twin"),("cb125r","CB125R")],
    "yamaha":       [("mt_07","MT-07"),("yzf_r1","YZF-R1"),("yzf_r3","YZF-R3"),("mt_09","MT-09"),("tracer_9","Tracer 9")],
    "kawasaki":     [("z900","Z900"),("ninja_400","Ninja 400"),("z650","Z650"),("versys_650","Versys 650"),("ninja_zx10r","Ninja ZX-10R")],
    "suzuki":       [("gsx_r750","GSX-R750"),("vstrom_650","V-Strom 650"),("sv650","SV650"),("gsx_s750","GSX-S750"),("burgman_400","Burgman 400")],
    "bmw":          [("r1250gs","R 1250 GS"),("s1000rr","S 1000 RR"),("f800gs","F 800 GS"),("r_ninet","R nineT"),("s1000xr","S 1000 XR")],
    "ducati":       [("panigale_v4","Panigale V4"),("monster","Monster"),("streetfighter_v4","Streetfighter V4"),("multistrada_v4","Multistrada V4"),("supersport_950","SuperSport 950")],
    "harley":       [("sportster_s","Sportster S"),("iron_883","Iron 883"),("fat_boy","Fat Boy"),("road_king","Road King"),("pan_america","Pan America 1250")],
    "royal_enfield":[("himalayan","Himalayan"),("meteor_350","Meteor 350"),("classic_350","Classic 350"),("interceptor_650","Interceptor 650"),("hunter_350","Hunter 350")],
    "ktm":          [("duke_390","Duke 390"),("adventure_890","Adventure 890"),("duke_790","Duke 790"),("rc_390","RC 390"),("super_duke_r","1290 Super Duke R")],
    "triumph":      [("bonneville_t120","Bonneville T120"),("tiger_900","Tiger 900"),("trident_660","Trident 660"),("street_twin","Street Twin"),("tiger_1200","Tiger 1200")],
    "aprilia":      [("rs_660","RS 660"),("tuono_660","Tuono 660"),("rsv4","RSV4"),("dorsoduro_900","Dorsoduro 900"),("sr_gt","SR GT")],
}
_COND_KAMYON = {
    "ford":       [("transit_custom","Transit Custom"),("transit","Transit"),("transit_connect","Transit Connect"),("transit_courier","Transit Courier"),("tourneo","Tourneo")],
    "fiat":       [("fiorino","Fiorino"),("doblo","Doblò"),("ducato","Ducato"),("scudo","Scudo"),("talento","Talento")],
    "volkswagen": [("caddy","Caddy"),("transporter","Transporter"),("crafter","Crafter"),("multivan","Multivan"),("california","California")],
    "mercedes":   [("sprinter","Sprinter"),("vito","Vito"),("viano","Viano"),("v_klasse","V-Klasse"),("citan","Citan")],
    "renault":    [("master","Master"),("trafic","Trafic"),("kangoo","Kangoo"),("express","Express"),("rapid","Rapid")],
    "opel":       [("vivaro","Vivaro"),("movano","Movano"),("combo","Combo"),("zafira_life","Zafira Life"),("crossland_cargo","Crossland Cargo")],
    "peugeot":    [("expert","Expert"),("boxer","Boxer"),("partner","Partner"),("traveller","Traveller"),("e_expert","e-Expert")],
    "isuzu":      [("d_max","D-Max"),("n_series","N-Series"),("f_series","F-Series"),("mu_x","MU-X"),("elf","Elf")],
    "iveco":      [("daily","Daily"),("eurocargo","Eurocargo"),("stralis","Stralis"),("s_way","S-Way"),("hi_way","Hi-Way")],
    "man":        [("tge","TGE"),("tgl","TGL"),("tgm","TGM"),("tgs","TGS"),("tgx","TGX")],
    "daf":        [("xf","XF"),("xg","XG"),("cf","CF"),("lf","LF"),("xg_plus","XG+")],
    "volvo":      [("fh","FH"),("fm","FM"),("fmx","FMX"),("fl","FL"),("fe","FE")],
    "scania":     [("r_serisi","R Serisi"),("s_serisi","S Serisi"),("p_serisi","P Serisi"),("g_serisi","G Serisi"),("l_serisi","L Serisi")],
}
_COND_TRAKTOR = {
    "new_holland":     [("t5","T5"),("t6","T6"),("t7","T7"),("tk4","TK4"),("td5","TD5")],
    "john_deere":      [("5075e","5075E"),("5090r","5090R"),("6110r","6110R"),("6130r","6130R"),("7r","7R")],
    "massey_ferguson": [("mf4700","4700 Serisi"),("mf5700","5700 Serisi"),("mf6700","6700 Serisi"),("mf7700","7700 Serisi"),("mf8700","8700 Serisi")],
    "kubota":          [("b_serisi","B Serisi"),("l_serisi","L Serisi"),("m_serisi","M Serisi"),("mx_serisi","MX Serisi"),("st_serisi","ST Serisi")],
    "fendt":           [("200_vario","200 Vario"),("300_vario","300 Vario"),("500_vario","500 Vario"),("700_vario","700 Vario"),("900_vario","900 Vario")],
    "case":            [("farmall_a","Farmall A"),("farmall_c","Farmall C"),("maxxum","Maxxum"),("puma","Puma"),("optum","Optum")],
    "tumosan":         [("60hp","60 HP"),("70hp","70 HP"),("80hp","80 HP"),("90hp","90 HP"),("100hp","100 HP")],
}
_COND_TEL = {
    "apple":    [("iphone_13","iPhone 13"),("iphone_14","iPhone 14"),("iphone_15","iPhone 15"),("iphone_15_pro","iPhone 15 Pro"),("iphone_16","iPhone 16")],
    "samsung":  [("galaxy_s23","Galaxy S23"),("galaxy_s24","Galaxy S24"),("galaxy_s24_ultra","Galaxy S24 Ultra"),("galaxy_a54","Galaxy A54"),("galaxy_a35","Galaxy A35")],
    "xiaomi":   [("redmi_note_13","Redmi Note 13"),("poco_x6_pro","Poco X6 Pro"),("14t_pro","14T Pro"),("redmi_12","Redmi 12"),("poco_m6_pro","Poco M6 Pro")],
    "huawei":   [("p50","P50"),("p60_pro","P60 Pro"),("nova_11","Nova 11"),("mate_60_pro","Mate 60 Pro"),("p40_lite","P40 Lite")],
    "oneplus":  [("oneplus_12","OnePlus 12"),("oneplus_11","OnePlus 11"),("nord_3","Nord 3"),("oneplus_12r","OnePlus 12R"),("nord_ce3","Nord CE 3")],
    "google":   [("pixel_7a","Pixel 7a"),("pixel_8","Pixel 8"),("pixel_8_pro","Pixel 8 Pro"),("pixel_9","Pixel 9"),("pixel_9_pro","Pixel 9 Pro")],
    "oppo":     [("find_x7","Find X7"),("reno_11","Reno 11"),("a78","A78"),("find_x6","Find X6"),("reno_10_pro","Reno 10 Pro")],
    "realme":   [("12_pro_plus","12 Pro+"),("gt_5","GT 5"),("c67","C67"),("11_pro_plus","11 Pro+"),("gt_neo_5","GT Neo 5")],
    "nokia":    [("g42","G42"),("c32","C32"),("g21","G21"),("xr21","XR21"),("g60","G60")],
    "motorola": [("moto_g84","Moto G84"),("edge_40","Edge 40"),("moto_g54","Moto G54"),("edge_50_pro","Edge 50 Pro"),("razr_40","Razr 40")],
}
_COND_LAPTOP = {
    "apple":   [("macbook_air_m2","MacBook Air M2"),("macbook_air_m3","MacBook Air M3"),("macbook_pro_14_m3","MacBook Pro 14\" M3"),("macbook_pro_16_m3","MacBook Pro 16\" M3"),("macbook_air_15_m2","MacBook Air 15\" M2")],
    "asus":    [("zenbook_14","ZenBook 14 OLED"),("rog_strix_g15","ROG Strix G15"),("vivobook_15","VivoBook 15"),("tuf_gaming_a15","TUF Gaming A15"),("proart_studiobook","ProArt Studiobook")],
    "lenovo":  [("thinkpad_e15","ThinkPad E15"),("ideapad_5","IdeaPad 5"),("legion_5","Legion 5"),("yoga_9i","Yoga 9i"),("thinkpad_x1_carbon","ThinkPad X1 Carbon")],
    "dell":    [("xps_13","XPS 13"),("xps_15","XPS 15"),("inspiron_15","Inspiron 15"),("latitude_5440","Latitude 5440"),("g15_gaming","G15 Gaming")],
    "hp":      [("pavilion_15","Pavilion 15"),("elitebook_840","EliteBook 840"),("victus_16","Victus 16"),("omen_16","Omen 16"),("probook_450","ProBook 450")],
    "msi":     [("stealth_15","Stealth 15"),("creator_m16","Creator M16"),("katana_15","Katana 15"),("gf63_thin","GF63 Thin"),("stealth_16","Stealth 16")],
    "acer":    [("swift_3","Swift 3"),("predator_helios","Predator Helios 300"),("aspire_5","Aspire 5"),("nitro_5","Nitro 5"),("swift_x","Swift X")],
    "toshiba": [("satellite_pro","Satellite Pro"),("tecra_a50","Tecra A50"),("portege_x30","Portégé X30"),("dynabook_e10","Dynabook E10"),("dynabook_cs50","Dynabook CS50")],
    "samsung": [("galaxy_book3","Galaxy Book3"),("galaxy_book3_pro","Galaxy Book3 Pro"),("galaxy_book3_ultra","Galaxy Book3 Ultra"),("galaxy_book3_360","Galaxy Book3 360"),("galaxy_book2_pro","Galaxy Book2 Pro")],
    "huawei":  [("matebook_d15","MateBook D15"),("matebook_14","MateBook 14"),("matebook_x_pro","MateBook X Pro"),("matebook_d14","MateBook D14"),("matebook_e","MateBook E")],
}
_COND_TABLET = {
    "apple":   [("ipad_air_m1","iPad Air M1"),("ipad_pro_11_m4","iPad Pro 11\" M4"),("ipad_10","iPad 10. Nesil"),("ipad_mini_6","iPad Mini 6"),("ipad_pro_13_m4","iPad Pro 13\" M4")],
    "samsung": [("tab_s9","Galaxy Tab S9"),("tab_a8","Galaxy Tab A8"),("tab_s8_plus","Galaxy Tab S8+"),("tab_s9_fe","Galaxy Tab S9 FE"),("tab_a9_plus","Galaxy Tab A9+")],
    "xiaomi":  [("pad_6","Pad 6"),("redmi_pad_se","Redmi Pad SE"),("pad_6_pro","Pad 6 Pro"),("redmi_pad_2","Redmi Pad 2"),("pad_5","Pad 5")],
    "huawei":  [("matepad_11","MatePad 11"),("matepad_pro_13","MatePad Pro 13.2\""),("matepad_t10s","MatePad T10s"),("matepad_se","MatePad SE"),("matepad_10_4","MatePad 10.4")],
    "oneplus": [("pad","OnePlus Pad"),("pad_go","OnePlus Pad Go"),("pad_2","OnePlus Pad 2"),("pad_pro","OnePlus Pad Pro"),("tab_r16","Tab R16")],
}
_COND_SAAT = {
    "rolex":     [("submariner","Submariner"),("datejust","Datejust"),("day_date","Day-Date"),("gmt_master_ii","GMT-Master II"),("daytona","Daytona")],
    "omega":     [("seamaster","Seamaster"),("speedmaster","Speedmaster"),("constellation","Constellation"),("de_ville","De Ville"),("aqua_terra","Aqua Terra")],
    "seiko":     [("presage","Presage"),("prospex","Prospex"),("5_sports","5 Sports"),("astron","Astron"),("alpinist","Alpinist")],
    "casio":     [("g_shock","G-Shock"),("edifice","Edifice"),("pro_trek","Pro Trek"),("wave_ceptor","Wave Ceptor"),("baby_g","Baby-G")],
    "tissot":    [("prx","PRX"),("t_race","T-Race"),("seastar","Seastar"),("le_locle","Le Locle"),("chemin_tourelles","Chemin des Tourelles")],
    "tag_heuer": [("carrera","Carrera"),("monaco","Monaco"),("aquaracer","Aquaracer"),("formula_1","Formula 1"),("link","Link")],
    "fossil":    [("minimalist","Minimalist"),("carlyle","Carlyle"),("neutra","Neutra"),("fenmore","Fenmore"),("gen_6","Gen 6")],
    "swatch":    [("big_bold","Big Bold"),("sistem51","Sistem51"),("skin","Skin"),("irony","Irony"),("gent","Gent")],
}
_COND_BISIKLET = {
    "giant":      [("contend","Contend"),("defy","Defy"),("tcx","TCX"),("anthem","Anthem"),("trance","Trance")],
    "trek":       [("fx","FX"),("marlin","Marlin"),("domane","Domane"),("emonda","Émonda"),("checkpoint","Checkpoint")],
    "specialized":[("allez","Allez"),("diverge","Diverge"),("stumpjumper","Stumpjumper"),("roubaix","Roubaix"),("rockhopper","Rockhopper")],
    "bianchi":    [("c_sport","C-Sport"),("sprint","Sprint"),("oltre_xr4","Oltre XR4"),("infinito","Infinito"),("impulso","Impulso")],
    "scott":      [("speedster","Speedster"),("sub_cross","Sub Cross"),("aspect","Aspect"),("contessa","Contessa"),("scale","Scale")],
    "merida":     [("big_nine","Big Nine"),("one_twenty","One-Twenty"),("scultura","Scultura"),("speeder","Speeder"),("reacto","Reacto")],
    "cannondale": [("quick","Quick"),("trail","Trail"),("topstone","Topstone"),("supersix_evo","SuperSix EVO"),("synapse","Synapse")],
}

_COND_OPTIONS: dict[tuple[str, str], dict[str, list[tuple[str, str]]]] = {
    ("otomobil",       "model"): _COND_ARAC,
    ("elektrikli_arac","model"): _COND_ELEKTRIK,
    ("motosiklet",     "model"): _COND_MOTO,
    ("kamyonet_minibus","model"): _COND_KAMYON,
    ("kamyon_tir",     "model"): _COND_KAMYON,
    ("traktor",        "model"): _COND_TRAKTOR,
    ("cep_telefonu",   "model"): _COND_TEL,
    ("bilgisayar_laptop","model"): _COND_LAPTOP,
    ("tablet",         "model"): _COND_TABLET,
    ("saat_giyim",     "model"): _COND_SAAT,
    ("bisiklet",       "model"): _COND_BISIKLET,
}


def upgrade() -> None:
    # ── Create tables ──────────────────────────────────────────────────────────
    op.create_table(
        "category_fields",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("subcategory", sa.String(80), nullable=False),
        sa.Column("key", sa.String(60), nullable=False),
        sa.Column("label_key", sa.String(80), nullable=False),
        sa.Column("type", sa.String(20), nullable=False),
        sa.Column("required", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("position", sa.SmallInteger(), nullable=False, server_default="0"),
        sa.Column("unit", sa.String(20), nullable=True),
        sa.Column("depends_on", sa.String(60), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_category_fields_subcategory_active", "category_fields", ["subcategory", "is_active"])

    op.create_table(
        "field_options",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("field_id", sa.Integer(), nullable=False),
        sa.Column("value", sa.String(80), nullable=False),
        sa.Column("label", sa.String(120), nullable=False),
        sa.Column("parent_option_value", sa.String(80), nullable=True),
        sa.Column("position", sa.SmallInteger(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["field_id"], ["category_fields.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_field_options_field_parent", "field_options", ["field_id", "parent_option_value", "is_active"])

    # ── Seed ──────────────────────────────────────────────────────────────────
    conn = op.get_bind()

    for subcategory, fields in _FIELDS.items():
        for (key, label_key, ftype, required, position, unit, depends_on) in fields:
            result = conn.execute(
                sa.text(
                    "INSERT INTO category_fields "
                    "(subcategory, key, label_key, type, required, position, unit, depends_on) "
                    "VALUES (:sub, :key, :lk, :t, :req, :pos, :unit, :dep) RETURNING id"
                ),
                {
                    "sub": subcategory,
                    "key": key,
                    "lk": label_key,
                    "t": ftype,
                    "req": required,
                    "pos": position,
                    "unit": unit,
                    "dep": depends_on,
                },
            )
            field_id = result.fetchone()[0]

            # top-level options
            top_opts = _TOP_OPTIONS.get((subcategory, key), [])
            for pos, (val, lbl) in enumerate(top_opts):
                conn.execute(
                    sa.text(
                        "INSERT INTO field_options (field_id, value, label, parent_option_value, position) "
                        "VALUES (:fid, :v, :l, NULL, :p)"
                    ),
                    {"fid": field_id, "v": val, "l": lbl, "p": pos},
                )

            # conditional options (brand → model)
            cond = _COND_OPTIONS.get((subcategory, key), {})
            for parent_val, child_opts in cond.items():
                for pos, (val, lbl) in enumerate(child_opts):
                    conn.execute(
                        sa.text(
                            "INSERT INTO field_options "
                            "(field_id, value, label, parent_option_value, position) "
                            "VALUES (:fid, :v, :l, :pv, :p)"
                        ),
                        {"fid": field_id, "v": val, "l": lbl, "pv": parent_val, "p": pos},
                    )


def downgrade() -> None:
    op.drop_index("ix_field_options_field_parent", table_name="field_options")
    op.drop_table("field_options")
    op.drop_index("ix_category_fields_subcategory_active", table_name="category_fields")
    op.drop_table("category_fields")
