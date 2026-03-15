import os
import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from app.config import settings
from app.models.user import User
from app.utils.auth import get_current_user

router = APIRouter(prefix="/api/upload", tags=["upload"])

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_SIZE = 10 * 1024 * 1024  # 10 MB


@router.post("")
async def upload_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(status_code=422, detail="Sadece JPEG, PNG, WebP veya GIF yüklenebilir")

    data = await file.read()
    if len(data) > MAX_SIZE:
        raise HTTPException(status_code=422, detail="Dosya boyutu 10 MB'ı geçemez")

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else "jpg"
    filename = f"{uuid.uuid4().hex}.{ext}"

    os.makedirs(settings.upload_dir, exist_ok=True)
    dest = os.path.join(settings.upload_dir, filename)
    with open(dest, "wb") as f:
        f.write(data)

    return {"url": f"/uploads/{filename}"}
