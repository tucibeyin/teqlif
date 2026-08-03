import asyncio
import os
import sys

# Bu script backend/ içinden çalıştırılır: python scripts/seed_emlak_listing_types.py
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.database import AsyncSessionLocal
from app.models.category_field import CategoryField, FieldOption
from sqlalchemy import select, delete, text


# Slug unification migration'ından sonra DB'deki gerçek subcategory slug'ları
SUBCATEGORIES = [
    'apartment',      # daire
    'house_villa',    # mustakil-ev-villa
    'land',           # arsa
    'field_garden',   # tarla-bahce
    'office',         # is-yeri-ofis
    'warehouse',      # depo-fabrika
    'building',       # bina
]

# Alt kategoriye göre hangi listing_type opsiyonları gösterilsin
OPTS_MAP = {
    'apartment':    [('satilik', 'optSatilik'), ('kiralik', 'optKiralik')],
    'house_villa':  [('satilik', 'optSatilik'), ('kiralik', 'optKiralik')],
    'building':     [('satilik', 'optSatilik'), ('kiralik', 'optKiralik')],
    'land':         [('satilik', 'optSatilik'), ('kiralik', 'optKiralik'), ('kat_karsiligi', 'optKatKarsiligi')],
    'field_garden': [('satilik', 'optSatilik'), ('kiralik', 'optKiralik'), ('kat_karsiligi', 'optKatKarsiligi')],
    'office':       [('satilik', 'optSatilik'), ('kiralik', 'optKiralik'), ('devren_satilik', 'optDevrenSatilik'), ('devren_kiralik', 'optDevrenKiralik')],
    'warehouse':    [('satilik', 'optSatilik'), ('kiralik', 'optKiralik'), ('devren_satilik', 'optDevrenSatilik'), ('devren_kiralik', 'optDevrenKiralik')],
}


async def seed_emlak_fields():
    print("Emlak kategorisi 'İlan Durumu' alanları güncelleniyor...")
    print(f"Hedef subcategory'ler: {SUBCATEGORIES}\n")

    async with AsyncSessionLocal() as session:

        # 1. Önce DB'de mevcut subcategory'leri doğrula
        existing_result = await session.execute(
            select(CategoryField.subcategory)
            .where(CategoryField.subcategory.in_(SUBCATEGORIES))
            .distinct()
        )
        found_subcats = {row[0] for row in existing_result.all()}
        missing = set(SUBCATEGORIES) - found_subcats
        if missing:
            print(f"⚠️  Uyarı: Bu subcategory'ler DB'de hiç kayıt içermiyor: {missing}")
            print("   Yine de devam ediliyor...\n")

        # 2. Eski 'listing_type' kayıtlarını temizle
        print("Eski 'listing_type' kayıtları temizleniyor...")
        stmt_fields = select(CategoryField).where(
            CategoryField.subcategory.in_(SUBCATEGORIES),
            CategoryField.key == 'listing_type'
        )
        result = await session.execute(stmt_fields)
        old_fields = result.scalars().all()

        if old_fields:
            old_field_ids = [f.id for f in old_fields]
            await session.execute(delete(FieldOption).where(FieldOption.field_id.in_(old_field_ids)))
            await session.execute(delete(CategoryField).where(CategoryField.id.in_(old_field_ids)))
            await session.flush()
            print(f"  {len(old_fields)} eski kayıt temizlendi.\n")
        else:
            print("  Temizlenecek eski kayıt yok.\n")

        # 3. Yeni alanları ve opsiyonları ekle
        for subcat in SUBCATEGORIES:
            opts = OPTS_MAP[subcat]
            print(f"[{subcat}] -> {len(opts)} opsiyon ekleniyor: {[o[0] for o in opts]}")

            # ORM yerine raw SQL — category_key modelde yok ama DB'de NOT NULL
            result = await session.execute(
                text("""
                    INSERT INTO category_fields
                        (subcategory, category_key, key, label_key, type, required, position, is_active)
                    VALUES
                        (:subcategory, :category_key, :key, :label_key, :type, :required, :position, :is_active)
                    RETURNING id
                """),
                {
                    'subcategory': subcat,
                    'category_key': 'real_estate',
                    'key': 'listing_type',
                    'label_key': 'fieldListingType',
                    'type': 'dropdown',
                    'required': True,
                    'position': 1,
                    'is_active': True,
                }
            )
            field_id = result.scalar_one()

            for i, (val, label) in enumerate(opts, start=1):
                session.add(FieldOption(
                    field_id=field_id,
                    value=val,
                    label=label,
                    position=i,
                    is_active=True
                ))

        # 4. Commit
        await session.commit()
        print("\n✅ Başarıyla tamamlandı!")
        print("Not: field-config endpoint cache'i (24h) otomatik expire olmadan görünmez.")
        print("Hızlı doğrulama için Redis cache'i temizleyebilirsin:")
        print("  redis-cli -n 0 KEYS 'fastapi-cache:*' | xargs redis-cli -n 0 DEL")


if __name__ == "__main__":
    asyncio.run(seed_emlak_fields())
