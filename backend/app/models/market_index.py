from datetime import date
from sqlalchemy import Date, Float
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

class ExchangeRates(Base):
    __tablename__ = "exchange_rates"
    
    # Date will be the primary key since we only have one record per day
    date: Mapped[date] = mapped_column(Date, primary_key=True, index=True)
    usd_try: Mapped[float] = mapped_column(Float, nullable=False)
    eur_try: Mapped[float] = mapped_column(Float, nullable=False)
