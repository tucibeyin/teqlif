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


class StoryItemOut(BaseModel):
    """
    Tek bir story öğesi — video hikayesi veya canlı yayın yönlendirmesi.

    story_type:
      'video'         → normal video hikayesi; video_url, expires_at, created_at dolu.
      'live_redirect' → kullanıcı şu an canlı; stream_id dolu, video alanları None.
    """

    id: int
    story_type: str  # 'video' | 'live_redirect'
    video_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    expires_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    stream_id: Optional[int] = None

    model_config = {"from_attributes": True}


class UserStoryGroupResponse(BaseModel):
    """
    Kullanıcı bazlı gruplanmış hybrid story listesi.

    Sıralama garantileri (service katmanında uygulanır):
      - `items` listesi: video hikayeleri created_at ASC, en sona live_redirect (varsa).
      - Grup listesi: en son aksiyonu (hikaye veya canlı yayın) olan kullanıcı başta.
    """

    user: StoryAuthorOut
    items: List[StoryItemOut]
    latest_activity_at: datetime


class StoryViewerOut(BaseModel):
    """Bir hikayeyi görüntüleyen kullanıcı özeti."""

    user_id: int
    username: str
    full_name: str
    profile_image_thumb_url: Optional[str] = None
    viewed_at: datetime

    model_config = {"from_attributes": True}


class StoryViewersResponse(BaseModel):
    """Bir hikayeyi görüntüleyen kullanıcıların listesi."""

    story_id: int
    viewers: List[StoryViewerOut]
    total: int


class MyStoriesResponse(BaseModel):
    """Giriş yapan kullanıcının kendi aktif hikayelerinin listesi."""

    items: List[StoryItemOut]
    total: int


# Geriye dönük uyumluluk — eski kod StoryOut adını kullanıyorsa import kırılmasın
StoryOut = StoryItemOut
