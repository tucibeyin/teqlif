"""Normalize legacy subcategory slugs to canonical English keys

Revision ID: zzzza_normalize_subcategory_slugs
Revises: zzzz_merge_category_and_flags
Create Date: 2026-07-28
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "zzzza_normalize_subcategory_slugs"
down_revision: Union[str, Sequence[str], None] = "zzzz_merge_category_and_flags"
branch_labels = None
depends_on = None

# legacy_slug -> canonical_slug
_SUBCAT_MAP = {
    # Vehicles
    "otomobil":            "automobile",
    "motosiklet":          "motorcycle",
    "elektrikli_arac":     "electric_vehicle",
    "elektrikli-arac":     "electric_vehicle",
    "kamyonet_minibus":    "van_minibus",
    "kamyonet-minibus":    "van_minibus",
    "kamyon_tir":          "truck",
    "kamyon-tir":          "truck",
    "traktor":             "tractor",
    "tekne_su_araci":      "boat",
    "tekne-su-araci":      "boat",
    "karavan":             "caravan",
    "yedek_parca":         "spare_parts",
    "vasita-yedek-parca":  "spare_parts",
    
    # Electronics
    "cep_telefonu":        "mobile_phone",
    "cep-telefonu":        "mobile_phone",
    "telefon":             "mobile_phone",
    "bilgisayar_laptop":   "laptop",
    "bilgisayar-laptop":   "laptop",
    "tablet":              "tablet",
    "tv_monitor":          "tv_monitor",
    "tv-monitor":          "tv_monitor",
    "kamera":              "camera",
    "ses_sistemi":         "audio_system",
    "ses-sistemi":         "audio_system",
    "akilli_saat_bileklik":"smartwatch",
    "akilli-saat-bileklik":"smartwatch",
    "oyun_konsol":         "gaming_console",
    "oyun_konsolu":        "gaming_console",
    "oyun-konsolu":        "gaming_console",
    "diger_elektronik":    "other_electronics",
    "diger-elektronik":    "other_electronics",
    
    # Real Estate
    "daire":               "apartment",
    "mustakil_ev_villa":   "house_villa",
    "mustakil-ev-villa":   "house_villa",
    "arsa":                "land",
    "tarla_bahce":         "field_garden",
    "tarla-bahce":         "field_garden",
    "is_yeri_ofis":        "office",
    "is-yeri-ofis":        "office",
    "depo_fabrika":        "warehouse",
    "depo-fabrika":        "warehouse",
    "bina":                "building",
    
    # Fashion
    "kadin_giyim":         "womens_clothing",
    "kadin-giyim":         "womens_clothing",
    "erkek_giyim":         "mens_clothing",
    "erkek-giyim":         "mens_clothing",
    "cocuk_giyim":         "kids_clothing",
    "cocuk-giyim":         "kids_clothing",
    "ayakkabi":            "shoes",
    "canta":               "bag",
    "canta_cuzdan":        "bag",
    "canta-cuzdan":        "bag",
    "taki_mucevher":       "jewelry",
    "taki-mucevher":       "jewelry",
    "saat_giyim":          "watch",
    "saat":                "watch",
    "sapka_kemer_aksesuar":"accessories",
    "aksesuar":            "accessories",
    
    # Home
    "mobilya":             "furniture",
    "mutfak_gerecleri":    "kitchen_equipment",
    "mutfak-pisirme":      "kitchen_equipment",
    "temizlik_ekipmani":   "cleaning_equipment",
    "temizlik-ekipmani":   "cleaning_equipment",
    "ev_tekstil":          "home_textile",
    "ev_tekstili":         "home_textile",
    "ev-tekstili":         "home_textile",
    "aydinlatma":          "lighting",
    "dekorasyon-aydinlatma":"lighting",
    "bahce_dis_mekan":     "garden_outdoor",
    "bahce-dis-mekan":     "garden_outdoor",
    "antika_koleksiyon":   "antique",
    "koleksiyon":          "antique",
    
    # Sports
    "bisiklet":            "bicycle",
    "spor_aleti_fitness":  "fitness_equipment",
    "fitness-spor-salonu": "fitness_equipment",
    "outdoor_camping":     "outdoor_camping",
    "outdoor-kamp":        "outdoor_camping",
    "top_takim_sporlari":  "team_sports",
    "takim-sporlari":      "team_sports",
    "doga_sporlari":       "outdoor_sports",
    "diger_spor":          "other_sports",
    
    # Books & Hobby
    "roman_hikaye":        "fiction",
    "roman-hikaye":        "fiction",
    "bilim_kurgu":         "sci_fi",
    "bilim-kurgu":         "sci_fi",
    "kisisel_gelisim":     "self_development",
    "kisisel-gelisim":     "self_development",
    "cocuk_kitaplari":     "kids_books",
    "cocuk-kitaplari":     "kids_books",
    "ders_okul":           "school_books",
    "ders-kitabi-akademik":"school_books",
    "muzik_sanat_kitap":   "arts_books",
    "koleksiyon_dergi":    "magazine",
    
    # Other
    "evcil_hayvan":        "pet",
    "evcil-hayvan":        "pet",
    "bebek_oyuncak":       "baby_toys",
    "oyuncak-cocuk-oyun":  "baby_toys",
    "muzik_aleti":         "musical_instrument",
    "muzik-aleti":         "musical_instrument",
    "foto_video_ekipmani": "photo_video",
    "yiyecek_tarim":       "food_agriculture",
    "saglik_guzellik":     "misc",
    "saglik-guzellik":     "misc",
    "diger":               "misc",
}


def upgrade() -> None:
    conn = op.get_bind()
    for legacy, canonical in _SUBCAT_MAP.items():
        if legacy == canonical:
            continue
        # Update listings
        conn.execute(
            sa.text("UPDATE listings SET subcategory = :canonical WHERE subcategory = :legacy"),
            {"canonical": canonical, "legacy": legacy},
        )
        # Update streams
        conn.execute(
            sa.text("UPDATE streams SET subcategory = :canonical WHERE subcategory = :legacy"),
            {"canonical": canonical, "legacy": legacy},
        )
        # Update user_interests
        conn.execute(
            sa.text("UPDATE user_interests SET subcategory = :canonical WHERE subcategory = :legacy"),
            {"canonical": canonical, "legacy": legacy},
        )
        # Update category_fields
        conn.execute(
            sa.text("UPDATE category_fields SET subcategory = :canonical WHERE subcategory = :legacy"),
            {"canonical": canonical, "legacy": legacy},
        )
        
    # Deactivate any remaining legacy keys in subcategories table
    conn.execute(
        sa.text("UPDATE subcategories SET is_active = false WHERE key = ANY(:keys) AND key != ALL(:canonical_keys)"),
        {"keys": list(_SUBCAT_MAP.keys()), "canonical_keys": list(set(_SUBCAT_MAP.values()))},
    )


def downgrade() -> None:
    pass
