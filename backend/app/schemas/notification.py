from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class NotificationOut(BaseModel):
    id: int
    user_id: int
    type: str
    title: str
    body: Optional[str] = None
    is_read: bool
    related_id: Optional[int] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class UnreadCountOut(BaseModel):
    count: int
