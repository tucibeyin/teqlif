from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class Translation(Base):
    __tablename__ = "translations"

    key: Mapped[str] = mapped_column(String(200), primary_key=True)
    lang: Mapped[str] = mapped_column(String(10), primary_key=True, index=True)
    value: Mapped[str] = mapped_column(Text, nullable=False)
