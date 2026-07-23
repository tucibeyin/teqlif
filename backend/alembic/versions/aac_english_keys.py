"""Rename all Turkish programmatic keys to English in DB and JSONB data

Revision ID: aac_english_keys
Revises: aab_yil_dropdown
Create Date: 2026-07-23

Changes:
- categories.key: vasita→vehicles, elektronik→electronics, etc.
- listings.category: same
- category_fields.subcategory: otomobil→automobile, etc.
- listings.subcategory: same
- category_fields.key: marka→brand, yil→year, etc.
- category_fields.label_key: extraField_marka→extraField_brand, etc.
- category_fields.depends_on: follows key renames
- field_options.value: beyaz→white, benzin→gasoline, etc.
- field_options.parent_option_value: grp:hasar_seviyesi→grp:damage_level
- listings.extra_fields JSONB: keys + values renamed
"""
from __future__ import annotations

import json
from typing import Any, Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "aac_english_keys"
down_revision: Union[str, Sequence[str], None] = "aab_yil_dropdown"
branch_labels = None
depends_on = None

# ── Mapping tables ────────────────────────────────────────────────────────────

CATEGORY_MAP = {
    "vasita":    "vehicles",
    "elektronik":"electronics",
    "giyim":     "fashion",
    "ev":        "home",
    "emlak":     "real_estate",
    "spor":      "sports",
    "kitap":     "books",
    "diger":     "other",
    "sohbet":    "chat",
}

SUBCATEGORY_MAP = {
    # vehicles
    "otomobil":         "automobile",
    "motosiklet":       "motorcycle",
    "elektrikli_arac":  "electric_vehicle",
    "kamyonet_minibus": "van_minibus",
    "kamyon_tir":       "truck",
    "traktor":          "tractor",
    "tekne_su_araci":   "boat",
    "karavan":          "caravan",
    "yedek_parca":      "spare_parts",
    # electronics
    "cep_telefonu":         "mobile_phone",
    "bilgisayar_laptop":    "laptop",
    "kamera":               "camera",
    "ses_sistemi":          "audio_system",
    "akilli_saat_bileklik": "smartwatch",
    "oyun_konsol":          "gaming_console",
    "diger_elektronik":     "other_electronics",
    # real_estate
    "daire":           "apartment",
    "mustakil_ev_villa":"house_villa",
    "arsa":            "land",
    "tarla_bahce":     "field_garden",
    "is_yeri_ofis":    "office",
    "depo_fabrika":    "warehouse",
    "bina":            "building",
    # fashion
    "kadin_giyim":          "womens_clothing",
    "erkek_giyim":          "mens_clothing",
    "cocuk_giyim":          "kids_clothing",
    "ayakkabi":             "shoes",
    "canta":                "bag",
    "taki_mucevher":        "jewelry",
    "saat_giyim":           "watch",
    "sapka_kemer_aksesuar": "accessories",
    # home
    "mobilya":            "furniture",
    "mutfak_gerecleri":   "kitchen_equipment",
    "temizlik_ekipmani":  "cleaning_equipment",
    "ev_tekstil":         "home_textile",
    "aydinlatma":         "lighting",
    "bahce_dis_mekan":    "garden_outdoor",
    "antika_koleksiyon":  "antique",
    # sports
    "bisiklet":           "bicycle",
    "spor_aleti_fitness": "fitness_equipment",
    "outdoor_kamp":       "outdoor_camping",
    "top_takim_sporlari": "team_sports",
    "doga_sporlari":      "outdoor_sports",
    "diger_spor":         "other_sports",
    # books
    "roman_hikaye":     "fiction",
    "bilim_kurgu":      "sci_fi",
    "kisisel_gelisim":  "self_development",
    "cocuk_kitaplari":  "kids_books",
    "ders_okul":        "school_books",
    "muzik_sanat_kitap":"arts_books",
    "koleksiyon_dergi": "magazine",
    # other
    "evcil_hayvan":       "pet",
    "bebek_oyuncak":      "baby_toys",
    "muzik_aleti":        "musical_instrument",
    "foto_video_ekipmani":"photo_video",
    "yiyecek_tarim":      "food_agriculture",
    "diger_kategori":     "misc",
}

FIELD_KEY_MAP = {
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
    "depolama":        "storage",
    "islemci":         "processor",
    "ekran_boyutu":    "screen_size",
    "oda_sayisi":      "room_count",
    "brut_m2":         "gross_sqm",
    "net_m2":          "net_sqm",
    "arsa_m2":         "land_sqm",
    "m2":              "sqm",
    "bina_yasi":       "building_age",
    "kat":             "floor",
    "kat_sayisi":      "floor_count",
    "daire_sayisi":    "unit_count",
    "isitma":          "heating",
    "esya_durumu":     "furnishing",
    "asansor":         "elevator",
    "otopark":         "parking",
    "tapu_durumu":     "title_deed",
    "kullanim_durumu": "land_use",
    "beden":           "size",
    "numara":          "shoe_size",
    "cinsiyet":        "gender",
    "malzeme":         "material",
    "altin_ayar":      "gold_carat",
    "gumus_ayar":      "silver_purity",
    "jant_boyutu":     "wheel_size",
    "spor_dali":       "sport_type",
    "kitap_ismi":      "book_title",
    "yazar":           "author",
    "yayinevi":        "publisher",
    "uzunluk":         "length",
    "calisma_saati":   "working_hours",
    "uyumlu_model":    "compatible_model",
    "parca_tipi":      "part_type",
    "irk":             "breed",
}

LABEL_KEY_MAP = {
    "extraField_marka":         "extraField_brand",
    "extraField_yil":           "extraField_year",
    "extraField_km":            "extraField_mileage",
    "extraField_renk":          "extraField_color",
    "extraField_yakit":         "extraField_fuel_type",
    "extraField_vites":         "extraField_transmission",
    "extraField_kasa_tipi":     "extraField_body_type",
    "extraField_hasar":         "extraField_damage_status",
    "extraField_tip":           "extraField_type",
    "extraField_motor_cc":      "extraField_engine_cc",
    "extraField_menzil":        "extraField_range",
    "extraField_depolama":      "extraField_storage",
    "extraField_islemci":       "extraField_processor",
    "extraField_ekran_boyutu":  "extraField_screen_size",
    "extraField_oda_sayisi":    "extraField_room_count",
    "extraField_brut_m2":       "extraField_gross_sqm",
    "extraField_net_m2":        "extraField_net_sqm",
    "extraField_arsa_m2":       "extraField_land_sqm",
    "extraField_m2":            "extraField_sqm",
    "extraField_bina_yasi":     "extraField_building_age",
    "extraField_kat":           "extraField_floor",
    "extraField_kat_sayisi":    "extraField_floor_count",
    "extraField_daire_sayisi":  "extraField_unit_count",
    "extraField_isitma":        "extraField_heating",
    "extraField_esya_durumu":   "extraField_furnishing",
    "extraField_asansor":       "extraField_elevator",
    "extraField_otopark":       "extraField_parking",
    "extraField_tapu_durumu":   "extraField_title_deed",
    "extraField_kullanim_durumu":"extraField_land_use",
    "extraField_beden":         "extraField_size",
    "extraField_numara":        "extraField_shoe_size",
    "extraField_cinsiyet":      "extraField_gender",
    "extraField_malzeme":       "extraField_material",
    "extraField_altin_ayar":    "extraField_gold_carat",
    "extraField_gumus_ayar":    "extraField_silver_purity",
    "extraField_jant_boyutu":   "extraField_wheel_size",
    "extraField_spor_dali":     "extraField_sport_type",
    "extraField_kitap_ismi":    "extraField_book_title",
    "extraField_yazar":         "extraField_author",
    "extraField_yayinevi":      "extraField_publisher",
    "extraField_uzunluk":       "extraField_length",
    "extraField_calisma_saati": "extraField_working_hours",
    "extraField_uyumlu_model":  "extraField_compatible_model",
    "extraField_parca_tipi":    "extraField_part_type",
    "extraField_irk":           "extraField_breed",
}

# General option value map (context-independent renames).
# Note: 'yok' is ambiguous — handled separately per field after key rename.
OPTION_VALUE_MAP: dict[str, str] = {
    # Colors
    "beyaz":      "white",
    "gri":        "gray",
    "siyah":      "black",
    "mavi":       "blue",
    "kirmizi":    "red",
    "yesil":      "green",
    "sari":       "yellow",
    "turuncu":    "orange",
    "mor":        "purple",
    "pembe":      "pink",
    "kahverengi": "brown",
    "bej":        "beige",
    "altin":      "gold",
    "gumus":      "silver",
    # Fuel
    "benzin":  "gasoline",
    "dizel":   "diesel",
    "hibrit":  "hybrid",
    "elektrik":"electric",
    "yelken":  "sail",
    # Transmission
    "manuel":       "manual",
    "otomatik":     "automatic",
    "yari_otomatik":"semi_automatic",
    # Damage (new multiselect)
    "boyali":             "painted",
    "kazali":             "accident",
    "hasar_kayitli":      "damage_record",
    "agir_hasar_kayitli": "heavy_damage_record",
    "hatasiz":            "flawless",
    # Damage (old dropdown, now soft-deleted)
    "hasarsiz": "no_damage",
    "hasarli":  "damaged_old",
    "degisen":  "repainted",
    # Building age
    "sifir": "new_build",
    # Heating options
    "kombi":         "combi_boiler",
    "dogalgaz":      "central_gas",
    "soba":          "stove",
    "klima":         "air_conditioning",
    "yerden_isitma": "underfloor_heating",
    # Furnishing
    "esyali":     "furnished",
    "yari_esyali":"semi_furnished",
    "bos":        "empty",
    # Yes (for elevator/parking) — 'var' only appears in yes/no context
    "var": "yes",
    # Title deed
    "kat_mulkiyeti": "condominium",
    "kat_irtifaki":  "floor_easement",
    "hisseli":       "shared_ownership",
    "arsa":          "land_title",
    # Land use
    "konut":    "residential",
    "ticari":   "commercial",
    "tarimsal": "agricultural",
    "sanayi":   "industrial",
    # Kids sizes
    "0_3ay":   "0_3m",
    "3_6ay":   "3_6m",
    "6_12ay":  "6_12m",
    "1_2yas":  "1_2y",
    "3_4yas":  "3_4y",
    "5_6yas":  "5_6y",
    "7_8yas":  "7_8y",
    "9_10yas": "9_10y",
    "11_12yas":"11_12y",
    "13_14yas":"13_14y",
    # Shoe type
    "spor":    "sneaker",
    "klasik":  "formal",
    "bot":     "boot",
    "sandalet":"sandal",
    "terlik":  "slipper",
    "topuklu": "heeled",
    # Bag/furniture material
    "deri":     "leather",
    "suni_deri":"faux_leather",
    "kumas":    "fabric",
    "kanvas":   "canvas",
    # Jewelry material
    "platin":    "platinum",
    "elmas":     "diamond",
    "dogal_tas": "natural_stone",
    # Gender
    "erkek": "male",
    "kadin": "female",
    # Furniture type
    "koltuk":  "sofa",
    "yatak":   "bed",
    "masa":    "table",
    "sandalye":"chair",
    "dolap":   "wardrobe",
    "raf":     "shelf",
    "sehpa":   "coffee_table",
    # Furniture material (extra, not in deri/kumas/metal/plastik/cam)
    "ahsap":   "wood",
    "metal":   "metal",
    "plastik": "plastic",
    "cam":     "glass",
    # Home textile
    "nevresim":"bedding_set",
    "yorgan":  "quilt",
    "yastik":  "pillow",
    "havlu":   "towel",
    "perde":   "curtain",
    "hali":    "rug",
    # Lighting
    "avize":       "chandelier",
    "abajur":      "lampshade",
    "masa_lambasi":"desk_lamp",
    "aplik":       "wall_lamp",
    "ayak_lambasi":"floor_lamp",
    # Bicycle type
    "dag":       "mountain",
    "yol":       "road",
    "sehir":     "city",
    "elektrikli":"electric_bike",
    "katlanan":  "folding",
    # Sports
    "futbol":      "football",
    "basketbol":   "basketball",
    "voleybol":    "volleyball",
    "tenis":       "tennis",
    "yuzme":       "swimming",
    "kosu":        "running",
    "boks":        "boxing",
    "doga_sporlari":"outdoor",
    # Pets
    "kopek":  "dog",
    "kedi":   "cat",
    "kus":    "bird",
    "balik":  "fish",
    "tavsan": "rabbit",
    # Music instruments
    "gitar": "guitar",
    "piyano":"piano",
    "davul": "drums",
    "keman": "violin",
    "flut":  "flute",
    # Photo/video equipment
    "kamera":"camera",
    "flas":  "flash",
    # Camera type
    "kompakt":"compact",
    # General
    "diger": "other",
    # Model values with Turkish suffix "_serisi" → "_series"
    "1_serisi": "1_series",
    "3_serisi": "3_series",
    "5_serisi": "5_series",
    "a_serisi": "a_series",
    "c_serisi": "c_series",
    "e_serisi": "e_series",
    "r_serisi": "r_series",
    "s_serisi": "s_series",
    "p_serisi": "p_series",
    "g_serisi": "g_series",
    "l_serisi": "l_series",
    "b_serisi": "b_series",
    "m_serisi": "m_series",
    "mx_serisi":"mx_series",
    "st_serisi":"st_series",
}

# Fields where 'yok' means 'no' (not 'none') — resolved after key rename
_YESNO_FIELDS = {"elevator", "parking"}


def _transform_extra_fields(ef: dict[str, Any]) -> dict[str, Any]:
    """Rename JSONB keys and values in extra_fields."""
    result: dict[str, Any] = {}
    for old_key, val in ef.items():
        new_key = FIELD_KEY_MAP.get(old_key, old_key)
        if isinstance(val, list):
            result[new_key] = [
                OPTION_VALUE_MAP.get(v, v) if isinstance(v, str) else v
                for v in val
            ]
        elif isinstance(val, str):
            if new_key in _YESNO_FIELDS and val == "yok":
                result[new_key] = "no"
            else:
                result[new_key] = OPTION_VALUE_MAP.get(val, val)
        else:
            result[new_key] = val
    return result


def upgrade() -> None:
    conn = op.get_bind()

    # 1. Rename main category keys in categories table
    for old, new in CATEGORY_MAP.items():
        conn.execute(
            sa.text("UPDATE categories SET key = :new WHERE key = :old"),
            {"old": old, "new": new},
        )

    # 2. Update listings.category
    for old, new in CATEGORY_MAP.items():
        conn.execute(
            sa.text("UPDATE listings SET category = :new WHERE category = :old"),
            {"old": old, "new": new},
        )

    # 3. Rename subcategory slugs in category_fields
    for old, new in SUBCATEGORY_MAP.items():
        conn.execute(
            sa.text("UPDATE category_fields SET subcategory = :new WHERE subcategory = :old"),
            {"old": old, "new": new},
        )

    # 4. Update listings.subcategory
    for old, new in SUBCATEGORY_MAP.items():
        conn.execute(
            sa.text("UPDATE listings SET subcategory = :new WHERE subcategory = :old"),
            {"old": old, "new": new},
        )

    # 5. Rename field keys (also updates depends_on in a second pass)
    for old, new in FIELD_KEY_MAP.items():
        conn.execute(
            sa.text("UPDATE category_fields SET key = :new WHERE key = :old"),
            {"old": old, "new": new},
        )

    # 6. Update depends_on references (e.g., 'marka' → 'brand')
    for old, new in FIELD_KEY_MAP.items():
        conn.execute(
            sa.text("UPDATE category_fields SET depends_on = :new WHERE depends_on = :old"),
            {"old": old, "new": new},
        )

    # 7. Update label_key values
    for old, new in LABEL_KEY_MAP.items():
        conn.execute(
            sa.text("UPDATE category_fields SET label_key = :new WHERE label_key = :old"),
            {"old": old, "new": new},
        )

    # 8. Rename grp:hasar_seviyesi → grp:damage_level in parent_option_value
    conn.execute(
        sa.text(
            "UPDATE field_options SET parent_option_value = 'grp:damage_level' "
            "WHERE parent_option_value = 'grp:hasar_seviyesi'"
        )
    )

    # 9. General option value renames (context-independent)
    for old, new in OPTION_VALUE_MAP.items():
        conn.execute(
            sa.text("UPDATE field_options SET value = :new WHERE value = :old"),
            {"old": old, "new": new},
        )

    # 10. Ambiguous 'yok': heating fields → 'none', elevator/parking → 'no'
    #     (field keys already renamed to 'heating', 'elevator', 'parking')
    conn.execute(
        sa.text(
            "UPDATE field_options SET value = 'none' "
            "WHERE value = 'yok' "
            "AND field_id IN (SELECT id FROM category_fields WHERE key = 'heating')"
        )
    )
    conn.execute(
        sa.text(
            "UPDATE field_options SET value = 'no' "
            "WHERE value = 'yok' "
            "AND field_id IN (SELECT id FROM category_fields WHERE key IN ('elevator', 'parking'))"
        )
    )

    # 11. Transform listings.extra_fields JSONB (Python loop for key+value renames)
    rows = conn.execute(
        sa.text(
            "SELECT id, extra_fields FROM listings "
            "WHERE extra_fields IS NOT NULL AND extra_fields::text != 'null'"
        )
    ).fetchall()
    for row in rows:
        lid, ef = row
        if not ef:
            continue
        new_ef = _transform_extra_fields(ef)
        if new_ef != ef:
            conn.execute(
                sa.text("UPDATE listings SET extra_fields = CAST(:ef AS jsonb) WHERE id = :id"),
                {"ef": json.dumps(new_ef, ensure_ascii=False), "id": lid},
            )


def downgrade() -> None:
    # Reverse mappings — partial: option value downgrades are best-effort
    conn = op.get_bind()

    CATEGORY_MAP_REV = {v: k for k, v in CATEGORY_MAP.items()}
    SUBCATEGORY_MAP_REV = {v: k for k, v in SUBCATEGORY_MAP.items()}
    FIELD_KEY_MAP_REV = {v: k for k, v in FIELD_KEY_MAP.items()}
    LABEL_KEY_MAP_REV = {v: k for k, v in LABEL_KEY_MAP.items()}
    OPTION_VALUE_MAP_REV = {v: k for k, v in OPTION_VALUE_MAP.items()}

    for old, new in CATEGORY_MAP_REV.items():
        conn.execute(sa.text("UPDATE categories SET key = :new WHERE key = :old"), {"old": old, "new": new})
    for old, new in CATEGORY_MAP_REV.items():
        conn.execute(sa.text("UPDATE listings SET category = :new WHERE category = :old"), {"old": old, "new": new})
    for old, new in SUBCATEGORY_MAP_REV.items():
        conn.execute(sa.text("UPDATE category_fields SET subcategory = :new WHERE subcategory = :old"), {"old": old, "new": new})
    for old, new in SUBCATEGORY_MAP_REV.items():
        conn.execute(sa.text("UPDATE listings SET subcategory = :new WHERE subcategory = :old"), {"old": old, "new": new})
    for old, new in FIELD_KEY_MAP_REV.items():
        conn.execute(sa.text("UPDATE category_fields SET key = :new WHERE key = :old"), {"old": old, "new": new})
    for old, new in FIELD_KEY_MAP_REV.items():
        conn.execute(sa.text("UPDATE category_fields SET depends_on = :new WHERE depends_on = :old"), {"old": old, "new": new})
    for old, new in LABEL_KEY_MAP_REV.items():
        conn.execute(sa.text("UPDATE category_fields SET label_key = :new WHERE label_key = :old"), {"old": old, "new": new})
    conn.execute(
        sa.text("UPDATE field_options SET parent_option_value = 'grp:hasar_seviyesi' WHERE parent_option_value = 'grp:damage_level'")
    )
    for old, new in OPTION_VALUE_MAP_REV.items():
        conn.execute(sa.text("UPDATE field_options SET value = :new WHERE value = :old"), {"old": old, "new": new})
    conn.execute(
        sa.text("UPDATE field_options SET value = 'yok' WHERE value = 'none' AND field_id IN (SELECT id FROM category_fields WHERE key = 'isitma')")
    )
    conn.execute(
        sa.text("UPDATE field_options SET value = 'yok' WHERE value = 'no' AND field_id IN (SELECT id FROM category_fields WHERE key IN ('asansor', 'otopark'))")
    )
