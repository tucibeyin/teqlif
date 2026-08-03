"""
export_category_fields.py
--------------------------
DB'deki tüm category_fields ve field_options verilerini okuyup
documents/categorization/ dizinine JSON dosyaları olarak yazar.
Her ana kategori için bir dosya oluşturulur: electronics.json, real_estate.json vb.

Çalıştırma (backend/ dizininden):
    python scripts/export_category_fields.py

Çıktı:
    documents/categorization/electronics.json
    documents/categorization/real_estate.json
    documents/categorization/vehicles.json
    ... vb.
"""

import asyncio
import json
import os
import sys
from collections import defaultdict

# backend/ içinden çalıştırılır
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.database import AsyncSessionLocal
from app.models.category_field import CategoryField, FieldOption
from sqlalchemy import select
from sqlalchemy.orm import selectinload

# Ana kategori → alt kategori mapping (aaa_slug_unification migration'dan)
CATEGORY_MAP = {
    "electronics": [
        "mobile_phone", "laptop", "tablet", "tv_monitor", "camera",
        "audio_system", "smartwatch", "gaming_console", "other_electronics",
    ],
    "vehicles": [
        "automobile", "motorcycle", "electric_vehicle", "van_minibus", "truck",
        "tractor", "boat", "caravan", "spare_parts",
    ],
    "real_estate": [
        "apartment", "house_villa", "land", "field_garden",
        "office", "warehouse", "building",
    ],
    "fashion": [
        "womens_clothing", "mens_clothing", "kids_clothing", "shoes",
        "bag", "jewelry", "watch", "accessories",
    ],
    "home": [
        "furniture", "kitchen_equipment", "cleaning_equipment", "home_textile",
        "lighting", "garden_outdoor", "antique",
    ],
    "sports": [
        "bicycle", "fitness_equipment", "outdoor_camping", "team_sports",
        "outdoor_sports", "other_sports",
    ],
    "books": [
        "fiction", "sci_fi", "self_development", "kids_books",
        "school_books", "arts_books", "magazine",
    ],
    "other": [
        "pet", "baby_toys", "musical_instrument", "photo_video",
        "food_agriculture", "hobby_craft", "health_beauty", "other_general",
    ],
}

# Ters map: subcat -> main_category
SUBCAT_TO_CATEGORY = {
    subcat: cat
    for cat, subcats in CATEGORY_MAP.items()
    for subcat in subcats
}


async def export_fields():
    output_base = os.path.abspath(
        os.path.join(os.path.dirname(__file__), '..', '..', 'documents', 'categorization')
    )
    os.makedirs(output_base, exist_ok=True)
    print(f"Cikti dizini: {output_base}\n")

    async with AsyncSessionLocal() as session:
        # Tüm aktif field'ları options ile birlikte çek
        result = await session.execute(
            select(CategoryField)
            .options(selectinload(CategoryField.options))
            .where(CategoryField.is_active.is_(True))
            .order_by(CategoryField.subcategory, CategoryField.position)
        )
        fields = result.scalars().all()

    print(f"Toplam {len(fields)} field bulundu.\n")

    # Ana kategoriye göre grupla
    by_category = defaultdict(lambda: defaultdict(list))
    unmapped_subcats = set()

    for field in fields:
        subcat = field.subcategory
        category = SUBCAT_TO_CATEGORY.get(subcat)
        if not category:
            unmapped_subcats.add(subcat)
            category = "unmapped"

        field_data = {
            "key": field.key,
            "label_key": field.label_key,
            "type": field.type,
            "required": field.required,
            "position": field.position,
            "unit": field.unit,
            "depends_on": field.depends_on,
            "options": []
        }

        for opt in sorted(field.options, key=lambda o: o.position):
            if not opt.is_active:
                continue
            field_data["options"].append({
                "value": opt.value,
                "label": opt.label,
                "parent_option_value": opt.parent_option_value,
                "exclusion_group": opt.exclusion_group,
                "is_exclusive": opt.is_exclusive,
                "position": opt.position,
            })

        by_category[category][subcat].append(field_data)

    if unmapped_subcats:
        print(f"UYARI - Haritalanmamis subcategory'ler (unmapped.json'a yazilacak): {unmapped_subcats}\n")

    # Her ana kategori için bir JSON dosyası yaz
    total_files = 0
    for category, subcats in sorted(by_category.items()):
        output = {
            "category": category,
            "subcategories": {}
        }
        for subcat, fields_list in sorted(subcats.items()):
            output["subcategories"][subcat] = fields_list

        file_path = os.path.join(output_base, f"{category}.json")
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)

        subcat_count = len(subcats)
        field_count = sum(len(v) for v in subcats.values())
        print(f"OK {category}.json yazildi -- {subcat_count} alt kategori, {field_count} field")
        total_files += 1

    print(f"\nToplam {total_files} dosya olusturuldu.")
    print(f"Dizin: {output_base}")
    print("\nBu dosyalari commit'leyip bana iletebilirsin.")


if __name__ == "__main__":
    asyncio.run(export_fields())
