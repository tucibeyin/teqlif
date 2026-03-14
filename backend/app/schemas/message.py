from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class MessageOut(BaseModel):
    id: int
    sender_id: int
    receiver_id: int
    sender_username: str
    content: str
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class ConversationOut(BaseModel):
    user_id: int
    username: str
    full_name: str
    last_message: str
    last_at: datetime
    unread_count: int


class SendMessageIn(BaseModel):
    receiver_id: int
    content: str = Field(..., min_length=1, max_length=1000)
