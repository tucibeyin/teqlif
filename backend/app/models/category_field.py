from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class CategoryField(Base):
    __tablename__ = "category_fields"
    __table_args__ = (
        Index("ix_category_fields_subcategory_active", "subcategory", "is_active"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    subcategory: Mapped[str] = mapped_column(String(80), nullable=False)
    key: Mapped[str] = mapped_column(String(60), nullable=False)
    label_key: Mapped[str] = mapped_column(String(80), nullable=False)
    type: Mapped[str] = mapped_column(String(20), nullable=False)  # text|number|dropdown
    required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    unit: Mapped[str | None] = mapped_column(String(20), nullable=True)
    depends_on: Mapped[str | None] = mapped_column(String(60), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    options: Mapped[list["FieldOption"]] = relationship(
        "FieldOption", back_populates="field", order_by="FieldOption.position"
    )


class FieldOption(Base):
    __tablename__ = "field_options"
    __table_args__ = (
        Index(
            "ix_field_options_field_parent",
            "field_id",
            "parent_option_value",
            "is_active",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    field_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("category_fields.id"), nullable=False
    )
    value: Mapped[str] = mapped_column(String(80), nullable=False)
    label: Mapped[str] = mapped_column(String(120), nullable=False)
    # NULL → top-level option; 'bmw' → only shown when parent = 'bmw'
    parent_option_value: Mapped[str | None] = mapped_column(String(80), nullable=True)
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    field: Mapped["CategoryField"] = relationship(
        "CategoryField", back_populates="options"
    )
