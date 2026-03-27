from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func
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
    video_path: Mapped[str] = mapped_column(String(500), nullable=False)
    video_url: Mapped[str] = mapped_column(String(500), nullable=False)
    thumbnail_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
