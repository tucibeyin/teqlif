from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


class StoryAuthorOut(BaseModel):
    """Hikayenin sahibine ait özet kullanıcı bilgisi."""

    id: int
    username: str
    full_name: str
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None

    model_config = {"from_attributes": True}


class StoryOut(BaseModel):
    """Tek bir hikaye öğesi."""

    id: int
    video_url: str
    thumbnail_url: Optional[str] = None
    expires_at: datetime
    created_at: datetime

    model_config = {"from_attributes": True}


class UserStoryGroupResponse(BaseModel):
    """
    Kullanıcı bazlı gruplanmış hikayeler.

    Sıralama garantileri (service katmanında uygulanır):
      - `stories` listesi: en eski → en yeni (created_at ASC)
      - Grup listesi: en son hikaye atan kullanıcı başta (latest_story_at DESC)
    """

    user: StoryAuthorOut
    stories: List[StoryOut]
    latest_story_at: datetime  # istemci tarafı sıralama/gösterim için referans
