"""Slug unification: subcategories table + rename category_fields to English slugs/keys

- Creates subcategories table (key, category_key FK, sort_order, is_active)
- Inserts all subcategory rows from kSubcategories
- Adds category_key column to category_fields
- Renames category_fields.subcategory from Turkish slugs to English slugs
- Renames category_fields.key / label_key / depends_on to English keys

Revision ID: aaa_slug_unification
Revises: zz_hasar_vasita_all
Create Date: 2026-07-26
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "aaa_slug_unification"
down_revision: Union[str, Sequence[str], None] = "zz_hasar_vasita_all"
branch_labels = None
depends_on = None

# ── Subcategory rows: (key, category_key, sort_order) ─────────────────────────
_SUBCATEGORIES = [
    # vehicles
    ("automobile",        "vehicles",    0),
    ("motorcycle",        "vehicles",    1),
    ("electric_vehicle",  "vehicles",    2),
    ("van_minibus",       "vehicles",    3),
    ("truck",             "vehicles",    4),
    ("tractor",           "vehicles",    5),
    ("boat",              "vehicles",    6),
    ("caravan",           "vehicles",    7),
    ("spare_parts",       "vehicles",    8),
    # electronics
    ("mobile_phone",      "electronics", 0),
    ("laptop",            "electronics", 1),
    ("tablet",            "electronics", 2),
    ("tv_monitor",        "electronics", 3),
    ("camera",            "electronics", 4),
    ("audio_system",      "electronics", 5),
    ("smartwatch",        "electronics", 6),
    ("gaming_console",    "electronics", 7),
    ("other_electronics", "electronics", 8),
    # real_estate
    ("apartment",         "real_estate", 0),
    ("house_villa",       "real_estate", 1),
    ("land",              "real_estate", 2),
    ("field_garden",      "real_estate", 3),
    ("office",            "real_estate", 4),
    ("warehouse",         "real_estate", 5),
    ("building",          "real_estate", 6),
    # fashion
    ("womens_clothing",   "fashion",     0),
    ("mens_clothing",     "fashion",     1),
    ("kids_clothing",     "fashion",     2),
    ("shoes",             "fashion",     3),
    ("bag",               "fashion",     4),
    ("jewelry",           "fashion",     5),
    ("watch",             "fashion",     6),
    ("accessories",       "fashion",     7),
    # home
    ("furniture",         "home",        0),
    ("kitchen_equipment", "home",        1),
    ("cleaning_equipment","home",        2),
    ("home_textile",      "home",        3),
    ("lighting",          "home",        4),
    ("garden_outdoor",    "home",        5),
    ("antique",           "home",        6),
    # sports
    ("bicycle",           "sports",      0),
    ("fitness_equipment", "sports",      1),
    ("outdoor_camping",   "sports",      2),
    ("team_sports",       "sports",      3),
    ("outdoor_sports",    "sports",      4),
    ("other_sports",      "sports",      5),
    # books
    ("fiction",           "books",       0),
    ("sci_fi",            "books",       1),
    ("self_development",  "books",       2),
    ("kids_books",        "books",       3),
    ("school_books",      "books",       4),
    ("arts_books",        "books",       5),
    ("magazine",          "books",       6),
    # other
    ("pet",               "other",       0),
    ("baby_toys",         "other",       1),
    ("musical_instrument","other",       2),
    ("photo_video",       "other",       3),
    ("food_agriculture",  "other",       4),
    ("misc",              "other",       5),
]

# ── Subcategory slug renames: Turkish DB key → English Flutter key ─────────────
_SUBCAT_RENAMES = {
    "otomobil":            "automobile",
    "motosiklet":          "motorcycle",
    "elektrikli_arac":     "electric_vehicle",
    "kamyonet_minibus":    "van_minibus",
    "kamyon_tir":          "truck",
    "traktor":             "tractor",
    "tekne_su_araci":      "boat",
    "karavan":             "caravan",
    "yedek_parca":         "spare_parts",
    "cep_telefonu":        "mobile_phone",
    "bilgisayar_laptop":   "laptop",
    "kamera":              "camera",
    "ses_sistemi":         "audio_system",
    "akilli_saat_bileklik":"smartwatch",
    "oyun_konsol":         "gaming_console",
    "daire":               "apartment",
    "mustakil_ev_villa":   "house_villa",
    "arsa":                "land",
    "tarla_bahce":         "field_garden",
    "is_yeri_ofis":        "office",
    "depo_fabrika":        "warehouse",
    "bina":                "building",
    "kadin_giyim":         "womens_clothing",
    "erkek_giyim":         "mens_clothing",
    "cocuk_giyim":         "kids_clothing",
    "ayakkabi":            "shoes",
    "canta":               "bag",
    "taki_mucevher":       "jewelry",
    "saat_giyim":          "watch",
    "sapka_kemer_aksesuar":"accessories",
    "mobilya":             "furniture",
    "ev_tekstil":          "home_textile",
    "aydinlatma":          "lighting",
    "antika_koleksiyon":   "antique",
    "bisiklet":            "bicycle",
    "spor_aleti_fitness":  "fitness_equipment",
    "top_takim_sporlari":  "team_sports",
    "doga_sporlari":       "outdoor_sports",
    "roman_hikaye":        "fiction",
    "bilim_kurgu":         "sci_fi",
    "kisisel_gelisim":     "self_development",
    "cocuk_kitaplari":     "kids_books",
    "ders_okul":           "school_books",
    "muzik_sanat_kitap":   "arts_books",
    "koleksiyon_dergi":    "magazine",
    "evcil_hayvan":        "pet",
    "muzik_aleti":         "musical_instrument",
    "foto_video_ekipmani": "photo_video",
}

# subcategory_key → category_key (for setting category_key column)
_SUBCAT_TO_CAT = {eng: cat for (eng, cat, _) in _SUBCATEGORIES}

# ── Field key renames: Turkish → English ──────────────────────────────────────
_KEY_RENAMES = {
    "marka":           "brand",
    "yil":             "year",
    "km":              "mileage",
    "yakit":           "fuel_type",
    "vites":           "transmission",
    "kasa_tipi":       "body_type",
    "renk":            "color",
    "hasar":           "damage_status",
    "tip":             "type",
    "motor_cc":        "engine_cc",
    "menzil_km":       "range_km",
    "calisma_saati":   "working_hours",
    "uzunluk":         "length",
    "uyumlu_model":    "compatible_model",
    "parca_tipi":      "part_type",
    "depolama":        "storage",
    "islemci":         "processor",
    "ekran_boyutu":    "screen_size",
    "oda_sayisi":      "room_count",
    "brut_m2":         "gross_sqm",
    "net_m2":          "net_sqm",
    "arsa_m2":         "land_sqm",
    "bina_yasi":       "building_age",
    "kat":             "floor",
    "kat_sayisi":      "floor_count",
    "isitma":          "heating",
    "esya_durumu":     "furnishing",
    "asansor":         "elevator",
    "otopark":         "parking",
    "tapu_durumu":     "title_deed",
    "kullanim_durumu": "land_use",
    "daire_sayisi":    "unit_count",
    "m2":              "sqm",
    "beden":           "size",
    "numara":          "shoe_size",
    "malzeme":         "material",
    "altin_ayar":      "gold_carat",
    "gumus_ayar":      "silver_purity",
    "cinsiyet":        "gender",
    "jant_boyutu":     "wheel_size",
    "spor_dali":       "sport_type",
    "kitap_ismi":      "book_title",
    "yazar":           "author",
    "yayinevi":        "publisher",
    "irk":             "breed",
}

# ── Label key renames ──────────────────────────────────────────────────────────
_LABEL_RENAMES = {
    "extraField_marka":           "extraField_brand",
    "extraField_yil":             "extraField_year",
    "extraField_km":              "extraField_mileage",
    "extraField_yakit":           "extraField_fuel_type",
    "extraField_vites":           "extraField_transmission",
    "extraField_kasa_tipi":       "extraField_body_type",
    "extraField_renk":            "extraField_color",
    "extraField_hasar":           "extraField_damage_status",
    "extraField_tip":             "extraField_type",
    "extraField_motor_cc":        "extraField_engine_cc",
    "extraField_menzil":          "extraField_menzil",   # label key unchanged (range_km key, menzil label)
    "extraField_calisma_saati":   "extraField_working_hours",
    "extraField_uzunluk":         "extraField_length",
    "extraField_uyumlu_model":    "extraField_compatible_model",
    "extraField_parca_tipi":      "extraField_part_type",
    "extraField_depolama":        "extraField_storage",
    "extraField_islemci":         "extraField_processor",
    "extraField_ekran_boyutu":    "extraField_screen_size",
    "extraField_oda_sayisi":      "extraField_room_count",
    "extraField_brut_m2":         "extraField_gross_sqm",
    "extraField_net_m2":          "extraField_net_sqm",
    "extraField_arsa_m2":         "extraField_land_sqm",
    "extraField_bina_yasi":       "extraField_building_age",
    "extraField_kat":             "extraField_floor",
    "extraField_kat_sayisi":      "extraField_floor_count",
    "extraField_isitma":          "extraField_heating",
    "extraField_esya_durumu":     "extraField_furnishing",
    "extraField_asansor":         "extraField_elevator",
    "extraField_otopark":         "extraField_parking",
    "extraField_tapu_durumu":     "extraField_title_deed",
    "extraField_kullanim_durumu": "extraField_land_use",
    "extraField_daire_sayisi":    "extraField_unit_count",
    "extraField_m2":              "extraField_sqm",
    "extraField_beden":           "extraField_size",
    "extraField_numara":          "extraField_shoe_size",
    "extraField_malzeme":         "extraField_material",
    "extraField_altin_ayar":      "extraField_gold_carat",
    "extraField_gumus_ayar":      "extraField_silver_purity",
    "extraField_cinsiyet":        "extraField_gender",
    "extraField_jant_boyutu":     "extraField_wheel_size",
    "extraField_spor_dali":       "extraField_sport_type",
    "extraField_kitap_ismi":      "extraField_book_title",
    "extraField_yazar":           "extraField_author",
    "extraField_yayinevi":        "extraField_publisher",
    "extraField_irk":             "extraField_breed",
}


def upgrade() -> None:
    conn = op.get_bind()

    # 1. Create subcategories table
    op.create_table(
        "subcategories",
        sa.Column("key",          sa.String(80),  primary_key=True),
        sa.Column("category_key", sa.String(80),  sa.ForeignKey("categories.key", ondelete="CASCADE"), nullable=False),
        sa.Column("sort_order",   sa.Integer(),   nullable=False, server_default="0"),
        sa.Column("is_active",    sa.Boolean(),   nullable=False, server_default="true"),
    )
    op.create_index("ix_subcategories_category_key", "subcategories", ["category_key"])

    # 2. Insert subcategory rows
    for (key, cat_key, sort) in _SUBCATEGORIES:
        conn.execute(
            sa.text(
                "INSERT INTO subcategories (key, category_key, sort_order) "
                "VALUES (:key, :cat, :sort) ON CONFLICT (key) DO NOTHING"
            ),
            {"key": key, "cat": cat_key, "sort": sort},
        )

    # 3. Add category_key column to category_fields
    op.add_column(
        "category_fields",
        sa.Column("category_key", sa.String(80), nullable=True),
    )

    # 4. Rename subcategory slugs in category_fields
    for tr_slug, en_slug in _SUBCAT_RENAMES.items():
        conn.execute(
            sa.text("UPDATE category_fields SET subcategory = :en WHERE subcategory = :tr"),
            {"en": en_slug, "tr": tr_slug},
        )

    # 5. Rename field keys (category_fields.key)
    for tr_key, en_key in _KEY_RENAMES.items():
        conn.execute(
            sa.text("UPDATE category_fields SET key = :en WHERE key = :tr"),
            {"en": en_key, "tr": tr_key},
        )

    # 6. Rename label keys (category_fields.label_key)
    for tr_lk, en_lk in _LABEL_RENAMES.items():
        if tr_lk != en_lk:
            conn.execute(
                sa.text("UPDATE category_fields SET label_key = :en WHERE label_key = :tr"),
                {"en": en_lk, "tr": tr_lk},
            )

    # 7. Rename depends_on references (marka → brand is the only cross-cutting one)
    conn.execute(
        sa.text("UPDATE category_fields SET depends_on = 'brand' WHERE depends_on = 'marka'")
    )

    # 8. Set category_key for all category_fields rows
    for en_slug, cat_key in _SUBCAT_TO_CAT.items():
        conn.execute(
            sa.text(
                "UPDATE category_fields SET category_key = :cat WHERE subcategory = :sub"
            ),
            {"cat": cat_key, "sub": en_slug},
        )

    # 9. Make category_key NOT NULL now that it's populated
    op.alter_column("category_fields", "category_key", nullable=False)


def downgrade() -> None:
    conn = op.get_bind()

    # Reverse field key renames
    _KEY_REV = {v: k for k, v in _KEY_RENAMES.items()}
    for en_key, tr_key in _KEY_REV.items():
        conn.execute(
            sa.text("UPDATE category_fields SET key = :tr WHERE key = :en"),
            {"tr": tr_key, "en": en_key},
        )

    # Reverse label key renames
    _LABEL_REV = {v: k for k, v in _LABEL_RENAMES.items() if k != v}
    for en_lk, tr_lk in _LABEL_REV.items():
        conn.execute(
            sa.text("UPDATE category_fields SET label_key = :tr WHERE label_key = :en"),
            {"tr": tr_lk, "en": en_lk},
        )

    # Reverse depends_on
    conn.execute(
        sa.text("UPDATE category_fields SET depends_on = 'marka' WHERE depends_on = 'brand'")
    )

    # Reverse subcategory slug renames
    _SUBCAT_REV = {v: k for k, v in _SUBCAT_RENAMES.items()}
    for en_slug, tr_slug in _SUBCAT_REV.items():
        conn.execute(
            sa.text("UPDATE category_fields SET subcategory = :tr WHERE subcategory = :en"),
            {"tr": tr_slug, "en": en_slug},
        )

    # Drop category_key column
    op.drop_column("category_fields", "category_key")

    # Drop subcategories table
    op.drop_index("ix_subcategories_category_key", table_name="subcategories")
    op.drop_table("subcategories")
