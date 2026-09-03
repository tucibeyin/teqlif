from sqlalchemy import String, Integer, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class District(Base):
    __tablename__ = "districts"
    __table_args__ = (
        Index("ix_districts_state_id", "state_id"),
        UniqueConstraint("state_id", "name", name="uq_districts_state_id_name"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    state_id: Mapped[int] = mapped_column(Integer, ForeignKey("states.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
