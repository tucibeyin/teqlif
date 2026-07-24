import logging

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi_cache.decorator import cache

from app.core.exceptions import NotFoundException
from app.database import get_db
from app.models.category_field import CategoryField, FieldOption
from app.schemas.field_config import ExtraFieldSchema, FieldConfigResponse, FieldOptionSchema

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/field-config", tags=["field-config"])


@router.get("/{subcategory}", response_model=FieldConfigResponse)
@cache(expire=86400)  # 24h — field schema değişmez, admin deploy'da cache sıfırlanır
async def get_field_config(
    subcategory: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> FieldConfigResponse:
    result = await db.execute(
        select(CategoryField)
        .where(CategoryField.subcategory == subcategory, CategoryField.is_active.is_(True))
        .order_by(CategoryField.position)
    )
    fields: list[CategoryField] = list(result.scalars().all())

    if not fields:
        raise NotFoundException(code="SUBCATEGORY_NOT_FOUND")

    field_ids = [f.id for f in fields]
    opts_result = await db.execute(
        select(FieldOption)
        .where(FieldOption.field_id.in_(field_ids), FieldOption.is_active.is_(True))
        .order_by(FieldOption.field_id, FieldOption.position)
    )
    all_options = opts_result.scalars().all()

    options_by_field: dict[int, list[FieldOption]] = {}
    for opt in all_options:
        options_by_field.setdefault(opt.field_id, []).append(opt)

    extra_fields = [
        ExtraFieldSchema(
            key=f.key,
            label_key=f.label_key,
            type=f.type,
            required=f.required,
            position=f.position,
            unit=f.unit,
            depends_on=f.depends_on,
            options=[
                FieldOptionSchema(
                    value=o.value,
                    label=o.label,
                    parent_option_value=o.parent_option_value,
                )
                for o in options_by_field.get(f.id, [])
            ],
        )
        for f in fields
    ]

    logger.info("[field-config] subcategory=%s fields=%d", subcategory, len(extra_fields))
    return FieldConfigResponse(subcategory=subcategory, fields=extra_fields)
