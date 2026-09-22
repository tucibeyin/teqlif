from decimal import Decimal, ROUND_HALF_UP


def to_price(value) -> Decimal:
    """Herhangi bir sayısal değeri Numeric(12,2) uyumlu Decimal'e çevirir."""
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
