from sqlalchemy import String, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class State(Base):
    __tablename__ = "states"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    country_code: Mapped[str] = mapped_column(String(2), nullable=False)
