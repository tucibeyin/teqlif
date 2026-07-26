from sqlalchemy import Boolean, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Subcategory(Base):
    __tablename__ = "subcategories"

    key: Mapped[str] = mapped_column(String(80), primary_key=True)
    category_key: Mapped[str] = mapped_column(
        String(80), ForeignKey("categories.key", ondelete="CASCADE"), nullable=False, index=True
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
