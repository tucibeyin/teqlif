import logging
import httpx
from xml.etree import ElementTree
from datetime import datetime
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models.market_index import ExchangeRates

logger = logging.getLogger(__name__)

TCMB_URL = "https://www.tcmb.gov.tr/kurlar/today.xml"


def _extract_rate(currency_elem, tag: str = "ForexBuying") -> float | None:
    """XML currency elementinden kur değeri çıkarır; eksik veya boş ise None döner."""
    node = currency_elem.find(tag)
    if node is not None and node.text and node.text.strip():
        try:
            return float(node.text.strip().replace(",", "."))
        except ValueError:
            pass
    return None


async def fetch_and_save_tcmb_rates(db: AsyncSession):
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(TCMB_URL, timeout=10.0)
            if resp.status_code != 200:
                logger.error("[TCMB] HTTP %s — kur güncellemesi atlandı.", resp.status_code)
                return

            root = ElementTree.fromstring(resp.text)

            usd_try: float | None = None
            eur_try: float | None = None

            for currency in root.findall("Currency"):
                code = currency.get("CurrencyCode")
                if code == "USD":
                    usd_try = _extract_rate(currency, "ForexBuying") or _extract_rate(currency, "BanknoteBuying")
                elif code == "EUR":
                    eur_try = _extract_rate(currency, "ForexBuying") or _extract_rate(currency, "BanknoteBuying")

        # Hafta sonu / tatil: ForexBuying ve BanknoteBuying her ikisi de boşsa
        # önceki iş gününün kurunu koru; cron işi çökmez, sistem çalışmaya devam eder.
        if usd_try is None:
            usd_try = await db.scalar(
                select(ExchangeRates.usd_try).order_by(ExchangeRates.date.desc()).limit(1)
            ) or 35.0
            logger.warning("[TCMB] USD kur verisi yok (hafta sonu/tatil) — önceki kur kullanıldı: %.4f", usd_try)

        if eur_try is None:
            eur_try = await db.scalar(
                select(ExchangeRates.eur_try).order_by(ExchangeRates.date.desc()).limit(1)
            ) or 38.0
            logger.warning("[TCMB] EUR kur verisi yok (hafta sonu/tatil) — önceki kur kullanıldı: %.4f", eur_try)

        today = datetime.now().date()
        stmt = (
            insert(ExchangeRates)
            .values(date=today, usd_try=usd_try, eur_try=eur_try)
            .on_conflict_do_update(
                index_elements=["date"],
                set_={"usd_try": usd_try, "eur_try": eur_try},
            )
        )
        await db.execute(stmt)
        await db.commit()
        logger.info("[TCMB] %s kuru güncellendi: USD=%.4f, EUR=%.4f", today, usd_try, eur_try)

    except Exception as exc:
        logger.error("[TCMB] Kur güncellemesi başarısız: %s", exc)


async def run_tcmb_job_once():
    """Arka planda tek seferlik (veya startup'ta) çalıştırmak için yardımcı metod."""
    async for db in get_db():
        await fetch_and_save_tcmb_rates(db)
        break
