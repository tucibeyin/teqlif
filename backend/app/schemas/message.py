from datetime import datetime
from typing import Literal, Optional
from pydantic import BaseModel, Field


class MessageOut(BaseModel):
    id: int
    sender_id: int
    receiver_id: int
    sender_username: str
    content: str
    content_type: str = "text"
    media_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    duration_secs: Optional[int] = None
    file_name: Optional[str] = None
    file_size: Optional[int] = None
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class ConversationOut(BaseModel):
    user_id: int
    username: str
    full_name: str
    last_message: str
    last_message_type: str = "text"
    last_at: datetime
    unread_count: int


class SendMessageIn(BaseModel):
    receiver_id: int
    content: str = Field(..., min_length=1, max_length=1000)
    listing_id: Optional[int] = None


MediaContentType = Literal["voice", "image", "video", "file"]
