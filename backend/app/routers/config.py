import logging
from typing import Dict, Any
from fastapi import APIRouter, Depends
from app.core.exceptions import ForbiddenException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.models.app_config import AppConfig
from app.utils.auth import get_current_user
from app.models.user import User

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/config", tags=["config"])

class VersionConfigRequest(BaseModel):
    ios_min_version: str
    ios_latest_version: str
    ios_store_url: str
    android_min_version: str
    android_latest_version: str
    android_store_url: str

@router.get("/version")
async def get_version_config(db: AsyncSession = Depends(get_db)):
    """
    Mobil uygulama versiyon kurallarını döndürür.
    """
    default_config = {
        "ios": {
            "min_version": "1.0.0",
            "latest_version": "1.0.0",
            "store_url": "https://apps.apple.com/tr/app/teqlif/id6759490205"
        },
        "android": {
            "min_version": "1.0.0",
            "latest_version": "1.0.0",
            "store_url": "https://play.google.com/store/apps/details?id=com.teqlif.app"
        }
    }
    
    try:
        result = await db.execute(select(AppConfig))
        configs = result.scalars().all()
        config_map = {c.key: c.value for c in configs}
        
        if "ios_min_version" in config_map:
            default_config["ios"]["min_version"] = config_map["ios_min_version"]
        if "ios_latest_version" in config_map:
            default_config["ios"]["latest_version"] = config_map["ios_latest_version"]
        if "ios_store_url" in config_map:
            default_config["ios"]["store_url"] = config_map["ios_store_url"]
        if "android_min_version" in config_map:
            default_config["android"]["min_version"] = config_map["android_min_version"]
        if "android_latest_version" in config_map:
            default_config["android"]["latest_version"] = config_map["android_latest_version"]
        if "android_store_url" in config_map:
            default_config["android"]["store_url"] = config_map["android_store_url"]
            
    except Exception as exc:
        logger.warning(f"AppConfig okuma hatası: {exc}")
        
    return default_config

@router.post("/version")
async def update_version_config(
    payload: VersionConfigRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Versiyon ayarlarını günceller. Sadece yetkili adminler kullanabilir.
    """
    if not current_user.is_admin:
        raise ForbiddenException()
        
    updates = {
        "ios_min_version": payload.ios_min_version,
        "ios_latest_version": payload.ios_latest_version,
        "ios_store_url": payload.ios_store_url,
        "android_min_version": payload.android_min_version,
        "android_latest_version": payload.android_latest_version,
        "android_store_url": payload.android_store_url,
    }
    
    for key, value in updates.items():
        result = await db.execute(select(AppConfig).where(AppConfig.key == key))
        cfg = result.scalar_one_or_none()
        if cfg:
            cfg.value = value
        else:
            cfg = AppConfig(key=key, value=value)
            db.add(cfg)
            
    await db.commit()
    return {"message": "Versiyon ayarları güncellendi."}
