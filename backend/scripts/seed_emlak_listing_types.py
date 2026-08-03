import asyncio
import os
import sys

# Backend dizinini yola ekle ki 'app' modülü bulunabilsin
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'backend')))

from app.database import async_session_maker
from app.models.category_field import CategoryField, FieldOption
from sqlalchemy import select, delete

async def seed_emlak_fields():
    print("Emlak kategorisi 'İlan Durumu' alanları güncelleniyor...")
    
    async with async_session_maker() as session:
        # Etkilenen alt kategoriler
        subcategories = [
            'daire', 'mustakil-ev-villa', 'arsa', 'tarla-bahce',
            'is-yeri-ofis', 'depo-fabrika', 'bina'
        ]
        
        # 1. Eski 'listing_type' kayıtlarını (eğer varsa) temizle
        print("Eski kayıtlar temizleniyor...")
        stmt_fields = select(CategoryField).where(
            CategoryField.subcategory.in_(subcategories),
            CategoryField.key == 'listing_type'
        )
        result = await session.execute(stmt_fields)
        old_fields = result.scalars().all()
        
        if old_fields:
            old_field_ids = [f.id for f in old_fields]
            await session.execute(delete(FieldOption).where(FieldOption.field_id.in_(old_field_ids)))
            await session.execute(delete(CategoryField).where(CategoryField.id.in_(old_field_ids)))
            await session.flush()

        # 2. Yeni alanları ve opsiyonları ekle
        for subcat in subcategories:
            print(f"[{subcat}] işleniyor...")
            # Field oluştur
            field = CategoryField(
                subcategory=subcat,
                key='listing_type',
                label_key='fieldListingType',
                type='dropdown',
                required=True,
                position=1,
                is_active=True
            )
            session.add(field)
            await session.flush()  # ID alabilmek için flush
            
            # Alt kategoriye göre eklenecek opsiyonlar
            opts = [
                ('satilik', 'optSatilik'),
                ('kiralik', 'optKiralik')
            ]
            
            if subcat in ['is-yeri-ofis', 'depo-fabrika']:
                opts.extend([
                    ('devren_satilik', 'optDevrenSatilik'),
                    ('devren_kiralik', 'optDevrenKiralik')
                ])
            elif subcat in ['arsa', 'tarla-bahce']:
                opts.append(('kat_karsiligi', 'optKatKarsiligi'))
                
            # Opsiyonları ekle
            for i, (val, label) in enumerate(opts, start=1):
                opt = FieldOption(
                    field_id=field.id,
                    value=val,
                    label=label,
                    position=i,
                    is_active=True
                )
                session.add(opt)
                
        # 3. Değişiklikleri kaydet
        await session.commit()
        print("✅ Başarıyla tamamlandı!")

if __name__ == "__main__":
    asyncio.run(seed_emlak_fields())
