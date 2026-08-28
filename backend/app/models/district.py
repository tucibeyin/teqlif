from sqlalchemy import String, Integer, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class District(Base):
    __tablename__ = "districts"
    __table_args__ = (
        Index("ix_districts_city_id", "city_id"),
        UniqueConstraint("city_id", "name", name="uq_districts_city_id_name"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    city_id: Mapped[int] = mapped_column(Integer, ForeignKey("cities.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
