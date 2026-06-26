from fastapi import APIRouter
from app.config import settings

router = APIRouter(prefix="/api", tags=["version"])


@router.get("/version")
async def get_version():
    """
    Minimum desteklenen uygulama versiyonlarını döner.
    Mobil uygulama splash'ta bu endpoint'i sorgular;
    mevcut versiyon min'den düşükse force-update ekranı gösterilir.
    """
    return {
        "min_ios_version": settings.min_ios_version,
        "min_android_version": settings.min_android_version,
    }
