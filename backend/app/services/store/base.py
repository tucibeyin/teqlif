from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime


@dataclass
class PurchaseResult:
    transaction_id: str        # consumable: tekil transactionId; subscription: originalTransactionId
    product_id: str            # teqlik_pack_100 | teqlif_pro_1m | ...
    environment: str           # "sandbox" | "production"
    purchased_at: datetime
    expires_at: datetime | None      # subscription; consumable → None
    subscription_id: str | None      # abonelik zinciri; consumable → None
    raw_payload: str                 # imzalı ham JWS (audit/dispute arşivi, 3-5 yıl)


class StoreVerifier(ABC):
    """Platform-agnostic IAP doğrulama soyut sınıfı.

    payload sözleşmesi (platform başına):
      Apple  → signedTransactionInfo JWS string
      Google → JSON: '{"purchase_token":"...","product_id":"...","package_name":"..."}'
      Web    → JSON: platform'a özgü; Verifier parse eder.
    Platform farklılıkları Verifier içinde kalır; dışarısı PurchaseResult ile konuşur.
    """

    @abstractmethod
    async def verify(self, payload: str) -> PurchaseResult:
        ...
