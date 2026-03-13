from datetime import datetime
from pydantic import BaseModel, field_validator


class StreamStart(BaseModel):
    title: str

    @field_validator("title")
    @classmethod
    def title_valid(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 3:
            raise ValueError("Başlık en az 3 karakter olmalı")
        if len(v) > 200:
            raise ValueError("Başlık en fazla 200 karakter olabilir")
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
