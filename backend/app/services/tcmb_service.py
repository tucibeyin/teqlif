import asyncio
import logging
import httpx
from xml.etree import ElementTree
from datetime import datetime
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models.market_index import ExchangeRates

logger = logging.getLogger(__name__)

TCMB_URL = "https://www.tcmb.gov.tr/kurlar/today.xml"

async def fetch_and_save_tcmb_rates(db: AsyncSession):
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(TCMB_URL, timeout=10.0)
            if resp.status_code != 200:
                logger.error(f"[TCMB] Failed to fetch rates. HTTP {resp.status_code}")
                return

            xml_data = resp.text
            root = ElementTree.fromstring(xml_data)

            usd_try = None
            eur_try = None

            for currency in root.findall("Currency"):
                code = currency.get("CurrencyCode")
                if code == "USD":
                    usd_try = float(currency.find("ForexBuying").text.replace(",", "."))
                elif code == "EUR":
                    eur_try = float(currency.find("ForexBuying").text.replace(",", "."))

            if usd_try and eur_try:
                today = datetime.now().date()
                
                # Check if today's rates already exist
                result = await db.execute(select(ExchangeRates).where(ExchangeRates.date == today))
                existing = result.scalar_one_or_none()
                
                if existing:
                    existing.usd_try = usd_try
                    existing.eur_try = eur_try
                else:
                    new_rate = ExchangeRates(date=today, usd_try=usd_try, eur_try=eur_try)
                    db.add(new_rate)
                    
                await db.commit()
                logger.info(f"[TCMB] Rates updated for {today}: USD={usd_try}, EUR={eur_try}")
            else:
                logger.error("[TCMB] Could not parse USD or EUR rates from XML.")

    except Exception as e:
        logger.error(f"[TCMB] Error fetching rates: {e}")

async def run_tcmb_job_once():
    """Arka planda tek seferlik (veya startup'ta) çalıştırmak için yardımcı metod."""
    async for db in get_db():
        await fetch_and_save_tcmb_rates(db)
        break
