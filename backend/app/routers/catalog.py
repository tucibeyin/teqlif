import hashlib
import json

from fastapi import APIRouter
from fastapi_cache.decorator import cache
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.category import Category
from app.models.category_field import CategoryField, FieldOption
from app.models.subcategory import Subcategory

router = APIRouter(prefix="/api/catalog", tags=["catalog"])


async def _build_catalog() -> dict:
    async with AsyncSessionLocal() as db:
        # Load all active categories
        cats_result = await db.execute(
            select(Category)
            .where(Category.status == "active")
            .order_by(Category.sort_order)
        )
        categories = cats_result.scalars().all()

        # Load all active subcategories
        subs_result = await db.execute(
            select(Subcategory)
            .where(Subcategory.is_active.is_(True))
            .order_by(Subcategory.category_key, Subcategory.sort_order)
        )
        subcategories = subs_result.scalars().all()

        # Load all active fields
        fields_result = await db.execute(
            select(CategoryField)
            .where(CategoryField.is_active.is_(True))
            .order_by(CategoryField.subcategory, CategoryField.position)
        )
        fields = fields_result.scalars().all()

        if fields:
            field_ids = [f.id for f in fields]
            opts_result = await db.execute(
                select(FieldOption)
                .where(FieldOption.field_id.in_(field_ids), FieldOption.is_active.is_(True))
                .order_by(FieldOption.field_id, FieldOption.position)
            )
            all_options = opts_result.scalars().all()
        else:
            all_options = []

    # Index options by field_id
    options_by_field: dict[int, list] = {}
    for opt in all_options:
        options_by_field.setdefault(opt.field_id, []).append({
            "value": opt.value,
            "label": opt.label,
            "label_key": f"opt_{opt.value}",
            "parent_option_value": opt.parent_option_value,
            "exclusion_group": opt.exclusion_group,
            "is_exclusive": opt.is_exclusive,
        })

    # Index fields by subcategory key
    fields_by_sub: dict[str, list] = {}
    for f in fields:
        fields_by_sub.setdefault(f.subcategory, []).append({
            "key": f.key,
            "label_key": f.label_key,
            "type": f.type,
            "required": f.required,
            "unit": f.unit,
            "depends_on": f.depends_on,
            "options": options_by_field.get(f.id, []),
        })

    # Index subcategories by category_key
    subs_by_cat: dict[str, list] = {}
    for sub in subcategories:
        subs_by_cat.setdefault(sub.category_key, []).append({
            "key": sub.key,
            "fields": fields_by_sub.get(sub.key, []),
        })

    # Build full tree
    catalog_categories = []
    for cat in categories:
        catalog_categories.append({
            "key": cat.key,
            "sort_order": cat.sort_order,
            "is_listable": cat.is_listable,
            "subcategories": subs_by_cat.get(cat.key, []),
        })

    return {"categories": catalog_categories}


def _compute_version(data: dict) -> str:
    payload = json.dumps(data, sort_keys=True, ensure_ascii=False)
    return hashlib.md5(payload.encode()).hexdigest()[:8]


@router.get("/version")
@cache(expire=86400)
async def get_catalog_version() -> dict:
    data = await _build_catalog()
    return {"version": _compute_version(data)}


@router.get("")
@cache(expire=86400)
async def get_catalog() -> dict:
    data = await _build_catalog()
    return {"version": _compute_version(data), **data}
