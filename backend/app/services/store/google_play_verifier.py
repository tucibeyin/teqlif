"""Google Play Developer API v3 — IAP satın alma doğrulaması.

payload sözleşmesi (JSON string):
  {"purchase_token": "...", "product_id": "...", "package_name": "..."}

  package_name opsiyonel — verilmezse settings.google_play_package_name kullanılır.

Consumable:  purchases.products.get
Abonelik:    purchases.subscriptionsv2.get
"""
from __future__ import annotations

import json
from datetime import datetime, timezone

import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account

from app.config import settings
from app.services.store.base import PurchaseResult, StoreVerifier
from app.core.exceptions import BadRequestException
from app.core.logger import get_logger

logger = get_logger(__name__)

_PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
_PLAY_BASE   = "https://androidpublisher.googleapis.com/androidpublisher/v3"

# product_id → subscription
_SUBSCRIPTION_IDS: frozenset[str] = frozenset({
    "teqlif_pro_1m",
    "teqlif_pro_3m",
    "teqlif_pro_6m",
    "teqlif_pro_12m",
})

_CONSUMABLE_IDS: frozenset[str] = frozenset({
    "teqlik_pack_100",
    "teqlik_pack_250",
    "teqlik_pack_500",
    "teqlik_pack_1000",
})

_VALID_PRODUCT_IDS: frozenset[str] = _CONSUMABLE_IDS | _SUBSCRIPTION_IDS


def _load_credentials() -> service_account.Credentials:
    sa_path = settings.google_play_service_account_path
    if not sa_path:
        raise BadRequestException(code="GOOGLE_PLAY_NOT_CONFIGURED")
    creds = service_account.Credentials.from_service_account_file(
        sa_path, scopes=[_PLAY_SCOPE]
    )
    return creds


def _get_access_token(creds: service_account.Credentials) -> str:
    """google-auth refresh — synchronous (networking) ama sadece token expire'da çalışır."""
    if not creds.valid:
        creds.refresh(GoogleAuthRequest())
    return creds.token


def _ms_to_dt(ms: str | int | None) -> datetime | None:
    if ms is None:
        return None
    try:
        return datetime.fromtimestamp(int(ms) / 1000, tz=timezone.utc)
    except (ValueError, OSError):
        return None


class GooglePlayVerifier(StoreVerifier):
    """Google Play Developer API v3 — consumable + subscription doğrulaması."""

    def __init__(self) -> None:
        self._creds: service_account.Credentials | None = None

    def _credentials(self) -> service_account.Credentials:
        if self._creds is None:
            self._creds = _load_credentials()
        return self._creds

    async def verify(self, payload: str) -> PurchaseResult:
        try:
            data = json.loads(payload)
        except json.JSONDecodeError as exc:
            raise BadRequestException(code="GOOGLE_PLAY_INVALID_PAYLOAD") from exc

        purchase_token = data.get("purchase_token", "").strip()
        product_id     = data.get("product_id", "").strip()
        package_name   = data.get("package_name", "").strip() or settings.google_play_package_name

        if not purchase_token or not product_id:
            raise BadRequestException(code="GOOGLE_PLAY_MISSING_FIELDS")

        if product_id not in _VALID_PRODUCT_IDS:
            raise BadRequestException(code="GOOGLE_PLAY_INVALID_PRODUCT")

        creds = self._credentials()
        token = _get_access_token(creds)
        headers = {"Authorization": f"Bearer {token}"}

        if product_id in _SUBSCRIPTION_IDS:
            return await self._verify_subscription(
                package_name, product_id, purchase_token, payload, headers
            )
        else:
            return await self._verify_consumable(
                package_name, product_id, purchase_token, payload, headers
            )

    async def _verify_consumable(
        self,
        package_name: str,
        product_id: str,
        purchase_token: str,
        raw_payload: str,
        headers: dict,
    ) -> PurchaseResult:
        url = (
            f"{_PLAY_BASE}/applications/{package_name}"
            f"/purchases/products/{product_id}/tokens/{purchase_token}"
        )
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=headers)

        if resp.status_code != 200:
            logger.error(
                "[GooglePlay] Consumable doğrulama başarısız | product=%s status=%s body=%s",
                product_id, resp.status_code, resp.text[:300],
            )
            raise BadRequestException(code="GOOGLE_PLAY_VERIFICATION_FAILED")

        body = resp.json()

        # purchaseState: 0=purchased, 1=cancelled, 2=pending
        if body.get("purchaseState", 1) != 0:
            raise BadRequestException(code="GOOGLE_PLAY_PURCHASE_NOT_COMPLETE")

        # consumptionState: 0=not consumed — Google sunucu tarafında consume eder
        # 1=consumed — zaten işlenmiş, replay koruması VerifyPurchaseCommand'da

        purchased_at = _ms_to_dt(body.get("purchaseTimeMillis")) or datetime.now(timezone.utc)
        # Consumable'da orderId benzersiz transaction kimliği
        tx_id = body.get("orderId") or purchase_token

        return PurchaseResult(
            transaction_id=str(tx_id),
            product_id=product_id,
            environment="production",  # Google Play Sandbox ayrı package_name gerektirir
            purchased_at=purchased_at,
            expires_at=None,
            subscription_id=None,
            raw_payload=raw_payload,
        )

    async def _verify_subscription(
        self,
        package_name: str,
        product_id: str,
        purchase_token: str,
        raw_payload: str,
        headers: dict,
    ) -> PurchaseResult:
        # subscriptionsv2 — hem yeni hem eski abonelikler için tek endpoint
        url = (
            f"{_PLAY_BASE}/applications/{package_name}"
            f"/purchases/subscriptionsv2/tokens/{purchase_token}"
        )
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=headers)

        if resp.status_code != 200:
            logger.error(
                "[GooglePlay] Subscription doğrulama başarısız | product=%s status=%s body=%s",
                product_id, resp.status_code, resp.text[:300],
            )
            raise BadRequestException(code="GOOGLE_PLAY_VERIFICATION_FAILED")

        body = resp.json()

        # subscriptionState: SUBSCRIPTION_STATE_ACTIVE | _PAUSED | _EXPIRED | _CANCELED | _IN_GRACE_PERIOD
        sub_state = body.get("subscriptionState", "")
        active_states = {
            "SUBSCRIPTION_STATE_ACTIVE",
            "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
        }
        if sub_state not in active_states:
            raise BadRequestException(code="GOOGLE_PLAY_SUBSCRIPTION_NOT_ACTIVE")

        # lineItems[0].expiryTime (ISO-8601)
        line_items = body.get("lineItems", [])
        expires_at: datetime | None = None
        if line_items:
            expiry_str = line_items[0].get("expiryTime")
            if expiry_str:
                try:
                    expires_at = datetime.fromisoformat(
                        expiry_str.replace("Z", "+00:00")
                    )
                except ValueError:
                    pass

        # startTime → purchased_at
        start_str = body.get("startTime", "")
        try:
            purchased_at = datetime.fromisoformat(start_str.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            purchased_at = datetime.now(timezone.utc)

        # latestOrderId — abonelik zincirinin en son orderId'si, tekil doğrulama için
        tx_id = body.get("latestOrderId") or purchase_token
        # externalAccountId yoksa purchase_token abonelik zincir kimliği olarak kullanılır
        sub_id = purchase_token

        return PurchaseResult(
            transaction_id=str(tx_id),
            product_id=product_id,
            environment="production",
            purchased_at=purchased_at,
            expires_at=expires_at,
            subscription_id=str(sub_id),
            raw_payload=raw_payload,
        )
