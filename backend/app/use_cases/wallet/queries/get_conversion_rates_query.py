from __future__ import annotations

from app.services.subscription.tier import CREDIT_COSTS_TEQLIK, TEQLIK_PER_STREAM_MINUTE


class GetConversionRatesQuery:
    """GET /api/wallet/conversion-rates — teqlik maliyet listesi.

    Tüm değerler tier.py'den okunur; frontend'e hardcode değer gömülmez.
    Redis cache (1 saat TTL) wallet.py router'da uygulanır.
    """

    def execute(self) -> dict:
        return {
            "teqlik_per_stream_minute": TEQLIK_PER_STREAM_MINUTE,
            "rates": [
                {
                    "key": "stream_minute",
                    "arb_key": "walletRateLiveStream",
                    "cost": TEQLIK_PER_STREAM_MINUTE,
                },
                {
                    "key": "boost",
                    "arb_key": "walletRateBoost",
                    "cost": CREDIT_COSTS_TEQLIK.get("boost", 50),
                },
                {
                    "key": "blast",
                    "arb_key": "walletRateBlast",
                    "cost": CREDIT_COSTS_TEQLIK.get("blast", 10),
                },
                {
                    "key": "reactivation",
                    "arb_key": "walletRateReactivation",
                    "cost": CREDIT_COSTS_TEQLIK.get("reactivation", 10),
                },
                {
                    "key": "ai_desc",
                    "arb_key": "walletRateAiDesc",
                    "cost": CREDIT_COSTS_TEQLIK.get("ai_desc", 5),
                },
            ],
        }
