"""
Beğeni modelleri — Listing, Story ve LiveStream için.

Cascade Kuralları:
  ListingLike  : listing silindiğinde (DB satırı) ve kullanıcı silindiğinde CASCADE.
  StoryLike    : story silindiğinde (cleanup) ve kullanıcı silindiğinde CASCADE.
  StreamLike   : yayın silindiğinde ve kullanıcı silindiğinde CASCADE.

Uniqueness:
  listing_likes : user_id + listing_id → bir kullanıcı bir ilanı yalnızca 1 kez beğenebilir.
  story_likes   : user_id + story_id   → bir kullanıcı bir hikayeyi yalnızca 1 kez beğenebilir.
  stream_likes  : kısıtlama yok — anlık kalp animasyonu; art arda beğeni eklenebilir.
"""
from datetime import datetime
from sqlalchemy import ForeignKey, UniqueConstraint, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ListingLike(Base):
    """İlan beğenisi. Bir kullanıcı aynı ilanı birden fazla kez beğenemez."""

    __tablename__ = "listing_likes"
    __table_args__ = (UniqueConstraint("user_id", "listing_id", name="uq_listing_like"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    listing_id: Mapped[int] = mapped_column(
        ForeignKey("listings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class StoryLike(Base):
    """Hikaye beğenisi. Bir kullanıcı aynı hikayeyi birden fazla kez beğenemez."""

    __tablename__ = "story_likes"
    __table_args__ = (UniqueConstraint("user_id", "story_id", name="uq_story_like"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    story_id: Mapped[int] = mapped_column(
        ForeignKey("stories.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class StreamLike(Base):
    """
    Canlı yayın kalp beğenisi.

    Uniqueness kısıtı yoktur — kullanıcı ekrana art arda basarak birden fazla
    kalp gönderebilir. Her kayıt bir animasyon eventi olarak loglanır.
    stream_id + user_id + created_at triosu anlık analiz için yeterlidir.
    """

    __tablename__ = "stream_likes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    stream_id: Mapped[int] = mapped_column(
        ForeignKey("live_streams.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
