import asyncio
import json
import os
import sys
import glob

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from app.database import AsyncSessionLocal
from app.models.category_field import CategoryField, FieldOption
from sqlalchemy import select
from app.config import settings
import redis.asyncio as aioredis

async def sync_fields():
    docs_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'documents', 'categorization'))
    json_files = glob.glob(os.path.join(docs_path, '*.json'))
    
    if not json_files:
        print("Kategorizasyon JSON dosyaları bulunamadı.")
        return

    print("Kategori JSON dosyaları okunuyor ve DB ile senkronize ediliyor...")
    async with AsyncSessionLocal() as db:
        res_fields = await db.execute(select(CategoryField))
        db_fields = list(res_fields.scalars().all())
        
        res_opts = await db.execute(select(FieldOption))
        db_opts = list(res_opts.scalars().all())
        
        field_lookup = {(f.subcategory, f.key): f for f in db_fields}
        opt_lookup = {(o.field_id, o.value): o for o in db_opts}
        
        seen_field_ids = set()
        seen_opt_ids = set()
        
        for file_path in json_files:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
            category_key = data.get("category")
            if not category_key or category_key == "unmapped":
                continue
                
            subcategories = data.get("subcategories", {})
            for subcat, fields in subcategories.items():
                for field_data in fields:
                    key = field_data["key"]
                    field_obj = field_lookup.get((subcat, key))
                    
                    if not field_obj:
                        field_obj = CategoryField(
                            category_key=category_key,
                            subcategory=subcat,
                            key=key,
                            label_key=field_data["label_key"],
                            type=field_data["type"],
                            required=field_data["required"],
                            position=field_data["position"],
                            unit=field_data.get("unit"),
                            depends_on=field_data.get("depends_on"),
                            is_active=True
                        )
                        db.add(field_obj)
                        await db.flush()
                    else:
                        field_obj.category_key = category_key
                        field_obj.label_key = field_data["label_key"]
                        field_obj.type = field_data["type"]
                        field_obj.required = field_data["required"]
                        field_obj.position = field_data["position"]
                        field_obj.unit = field_data.get("unit")
                        field_obj.depends_on = field_data.get("depends_on")
                        field_obj.is_active = True
                        
                    seen_field_ids.add(field_obj.id)
                    
                    options = field_data.get("options", [])
                    for opt_data in options:
                        val = opt_data["value"]
                        opt_obj = opt_lookup.get((field_obj.id, val))
                        
                        if not opt_obj:
                            opt_obj = FieldOption(
                                field_id=field_obj.id,
                                value=val,
                                label=opt_data["label"],
                                parent_option_value=opt_data.get("parent_option_value"),
                                exclusion_group=opt_data.get("exclusion_group"),
                                is_exclusive=opt_data.get("is_exclusive", False),
                                position=opt_data.get("position", 0),
                                is_active=True
                            )
                            db.add(opt_obj)
                            await db.flush()
                        else:
                            opt_obj.label = opt_data["label"]
                            opt_obj.parent_option_value = opt_data.get("parent_option_value")
                            opt_obj.exclusion_group = opt_data.get("exclusion_group")
                            opt_obj.is_exclusive = opt_data.get("is_exclusive", False)
                            opt_obj.position = opt_data.get("position", 0)
                            opt_obj.is_active = True
                            
                        seen_opt_ids.add(opt_obj.id)
                        
        deactivated_fields = 0
        for f in db_fields:
            if f.id not in seen_field_ids and f.is_active:
                f.is_active = False
                deactivated_fields += 1
                
        deactivated_opts = 0
        for o in db_opts:
            if o.id not in seen_opt_ids and o.is_active:
                o.is_active = False
                deactivated_opts += 1

        await db.commit()
        print(f"Senkronizasyon tamamlandı.")
        print(f"Toplam Field: {len(seen_field_ids)} aktif, {deactivated_fields} inaktif edildi.")
        print(f"Toplam Option: {len(seen_opt_ids)} aktif, {deactivated_opts} inaktif edildi.")
        
    try:
        r = aioredis.from_url(settings.redis_url)
        keys = await r.keys("teqlif:cache:*")
        if keys:
            await r.delete(*keys)
            print(f"Redis API cache temizlendi. ({len(keys)} key silindi)")
        await r.aclose()
    except Exception as e:
        print(f"Cache temizlenirken hata oluştu: {e}")

if __name__ == "__main__":
    asyncio.run(sync_fields())
