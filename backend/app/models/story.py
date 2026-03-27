from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Story(Base):
    """
    Kullanıcı hikayesi (Video Story).

    video_path : Sunucu diskindeki fiziksel yol (temizlik için gerekli).
    video_url  : İstemciye sunulan erişim URL'i.
    expires_at : Bu tarihten sonra içerik geçersizdir; cleanup tarafından silinir.
    """

    __tablename__ = "stories"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    media_type: Mapped[str] = mapped_column(String(10), nullable=False, server_default="video")
    video_path: Mapped[str] = mapped_column(String(500), nullable=False)
    video_url: Mapped[str] = mapped_column(String(500), nullable=False)
    thumbnail_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


class StoryView(Base):
    """
    Hikaye görüntüleme kaydı.

    story_id + viewer_id çifti UNIQUE — aynı kişi birden fazla kayıt üretmez.
    ondelete="CASCADE": Story silindiğinde (cleanup) kayıtlar otomatik silinir.
    Hikaye sahibinin kendi görüntülemesi service katmanında filtrelenir.
    """

    __tablename__ = "story_views"
    __table_args__ = (UniqueConstraint("story_id", "viewer_id", name="uq_story_viewer"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    story_id: Mapped[int] = mapped_column(
        ForeignKey("stories.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    viewer_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    viewed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
