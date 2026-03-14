from datetime import datetime
from pydantic import BaseModel, field_validator


VALID_CATEGORIES = {
    "elektronik", "giyim", "ev", "vasita", "spor", "kitap", "diger"
}


class StreamStart(BaseModel):
    title: str
    category: str

    @field_validator("title")
    @classmethod
    def title_valid(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 3:
            raise ValueError("Başlık en az 3 karakter olmalı")
        if len(v) > 200:
            raise ValueError("Başlık en fazla 200 karakter olabilir")
        return v

    @field_validator("category")
    @classmethod
    def category_valid(cls, v: str) -> str:
        v = v.strip().lower()
        if v not in VALID_CATEGORIES:
            raise ValueError(f"Geçersiz kategori. Geçerli değerler: {', '.join(VALID_CATEGORIES)}")
        return v


class StreamHostOut(BaseModel):
    id: int
    username: str
    full_name: str
    model_config = {"from_attributes": True}


class StreamOut(BaseModel):
    id: int
    room_name: str
    title: str
    category: str
    host: StreamHostOut
    viewer_count: int
    started_at: datetime
    model_config = {"from_attributes": True}


class StreamTokenOut(BaseModel):
    stream_id: int
    room_name: str
    livekit_url: str
    token: str


class JoinTokenOut(BaseModel):
    stream_id: int
    room_name: str
    livekit_url: str
    token: str
    title: str
    host_username: str
