from datetime import datetime
from sqlalchemy import Integer, ForeignKey, func, Index, DateTime
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class MassNotificationCampaign(Base):
    """
    Kullanıcıların ilanları veya canlı yayınları için gönderdiği
    Toplu Kitle Bildirimi (Mass Notification) kampanyalarının kayıtları.
    """

    __tablename__ = "mass_notification_campaigns"
    __table_args__ = (
        Index("ix_mass_notif_user_created", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    listing_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("listings.id", ondelete="SET NULL"), nullable=True, index=True
    )
    stream_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("live_streams.id", ondelete="SET NULL"), nullable=True, index=True
    )

    # Bildirim İstatistikleri
    target_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    sent_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    click_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # Maliyet Bilgileri
    spent_tuci: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    spent_free_credits: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
