from fastapi import APIRouter, Request, Depends
from sqlalchemy import select
from app.models.enums import CategoryStatus
from app.database import AsyncSessionLocal
from app.models.category import Category
from app.models.user import User
from app.utils.auth import get_current_user_optional
from app.utils.i18n import _get_t

router = APIRouter(prefix="/api/categories", tags=["categories"])

@router.get("")
async def list_categories(
    request: Request,
    current_user: User | None = Depends(get_current_user_optional)
):
    lang = "tr"
    if current_user and current_user.locale:
        lang = current_user.locale
    else:
        al = request.headers.get("accept-language", "")
        if "en" in al: lang = "en"
        elif "ru" in al: lang = "ru"
        elif "ar" in al: lang = "ar"

    t = _get_t(lang)

    context = request.query_params.get("context")

    async with AsyncSessionLocal() as db:
        query = select(Category).where(Category.status == CategoryStatus.ACTIVE)
        if context != "stream":
            query = query.where(Category.is_listable.is_(True))
            
        result = await db.execute(query.order_by(Category.sort_order))
        cats = result.scalars().all()
        
        return [
            {
                "key": c.key,
                "label": t.get(f"cat_{c.key}", c.label)
            } for c in cats
        ]
