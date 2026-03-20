from datetime import datetime
from pydantic import BaseModel


class BlockedUserOut(BaseModel):
    id: int
    username: str
    full_name: str
    profile_image_url: str | None

    model_config = {"from_attributes": True}


class BlockStatusOut(BaseModel):
    is_blocked: bool
