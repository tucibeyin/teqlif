"""App Store Server API v1 — subscription durumu sorgulama (pull-based reconciliation).

Apple'ın push notification'larına ek olarak, backend aktif olarak subscription
durumunu sorgulayabilir. Bu 3-katmanlı reconciliation mimarisinin pull bacağıdır:

  Client → Backend (verify)   : /wallet/purchase/verify
  Apple  → Backend (push)     : /wallet/store-notifications/apple
  Backend → Apple (pull)      : Bu modül — /inApps/v1/subscriptions/{originalTxId}

Referans: https://developer.apple.com/documentation/appstoreserverapi
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import httpx
import jwt

from app.config import settings
from app.core.logger import get_logger
from app.services.store.apple_verifier import verify_signed_payload_jws

logger = get_logger(__name__)

_PROD_BASE = "https://api.storekit.itunes.apple.com"
_SANDBOX_BASE = "https://api.storekit-sandbox.itunes.apple.com"

# Apple subscription status kodları
STATUS_ACTIVE = 1
STATUS_EXPIRED = 2
STATUS_BILLING_RETRY = 3
STATUS_GRACE_PERIOD = 4
STATUS_REVOKED = 5

_ACTIVE_STATUSES = {STATUS_ACTIVE, STATUS_BILLING_RETRY, STATUS_GRACE_PERIOD}


@dataclass
class SubscriptionStatus:
    original_transaction_id: str
    product_id: str
    status: int           # Apple status kodu (1-5)
    expires_at: datetime | None
    environment: str      # "Production" | "Sandbox"

    @property
    def is_active(self) -> bool:
        return self.status in _ACTIVE_STATUSES


def _load_private_key() -> str:
    """Config'den private key PEM içeriğini yükler."""
    if settings.appstore_private_key_path:
        path = Path(settings.appstore_private_key_path)
        if path.exists():
            return path.read_text().strip()
    if settings.appstore_private_key:
        return settings.appstore_private_key.strip().replace("\\n", "\n")
    return ""


def _build_jwt() -> str:
    """App Store Connect API için kısa ömürlü Bearer JWT üretir.

    Spesifikasyon: alg=ES256, aud=appstoreconnect-v1, exp max 1 saat.
    Biz 60 sn kullanıyoruz — tek istek için yeterli, sızıntı riskini minimuma indirir.
    """
    private_key = _load_private_key()
    if not private_key:
        raise RuntimeError("App Store Connect API private key yapılandırılmamış")

    now = int(time.time())
    payload = {
        "iss": settings.appstore_issuer_id,
        "iat": now,
        "exp": now + 60,
        "aud": "appstoreconnect-v1",
        "bid": settings.ios_bundle_id,
    }
    return jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": settings.appstore_key_id},
    )


def is_configured() -> bool:
    """App Store Server API credentials yapılandırılmış mı?"""
    return bool(
        settings.appstore_issuer_id
        and settings.appstore_key_id
        and (settings.appstore_private_key_path or settings.appstore_private_key)
    )


async def get_subscription_status(
    original_transaction_id: str,
) -> SubscriptionStatus | None:
    """Verilen originalTransactionId için Apple'dan anlık subscription durumunu çeker.

    Dönüş: En son aktif transaction'ın SubscriptionStatus'u.
    Aktif transaction yoksa (expired, revoked) yine de en son transaction döner.
    API erişilemezse None döner — caller gracefully handle etmeli.
    """
    if not is_configured():
        logger.warning("[AppleServerAPI] Credentials yapılandırılmamış, sync atlanıyor")
        return None

    base = _SANDBOX_BASE if settings.iap_allow_sandbox else _PROD_BASE
    url = f"{base}/inApps/v1/subscriptions/{original_transaction_id}"

    try:
        token = _build_jwt()
    except Exception as exc:
        logger.error("[AppleServerAPI] JWT üretilemedi: %s", exc)
        return None

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                url,
                headers={"Authorization": f"Bearer {token}"},
            )
    except httpx.RequestError as exc:
        logger.warning("[AppleServerAPI] Ağ hatası: %s", exc)
        return None

    if resp.status_code == 404:
        logger.info("[AppleServerAPI] Subscription bulunamadı | orig_tx=%s", original_transaction_id)
        return None

    if resp.status_code != 200:
        logger.warning(
            "[AppleServerAPI] Beklenmedik HTTP %s | orig_tx=%s body=%s",
            resp.status_code, original_transaction_id, resp.text[:200],
        )
        return None

    body = resp.json()

    # data: list[subscriptionGroupItem] → lastTransactions içinden en son aktif olanı seç
    best: SubscriptionStatus | None = None
    for group in body.get("data", []):
        for item in group.get("lastTransactions", []):
            status_code = item.get("status", 0)
            signed_tx = item.get("signedTransactionInfo")
            if not signed_tx:
                continue

            try:
                tx_claims = verify_signed_payload_jws(signed_tx)
            except Exception as exc:
                logger.warning("[AppleServerAPI] JWS doğrulanamadı: %s", exc)
                continue

            product_id = tx_claims.get("productId", "")
            expires_ms = tx_claims.get("expiresDate", 0)
            expires_at = (
                datetime.fromtimestamp(expires_ms / 1000, tz=timezone.utc)
                if expires_ms
                else None
            )
            environment = tx_claims.get("environment", "Production")
            orig_tx = str(tx_claims.get("originalTransactionId", original_transaction_id))

            candidate = SubscriptionStatus(
                original_transaction_id=orig_tx,
                product_id=product_id,
                status=status_code,
                expires_at=expires_at,
                environment=environment,
            )

            # Aktif olanı tercih et; yoksa en yüksek bitiş tarihini al
            if best is None:
                best = candidate
            elif candidate.is_active and not best.is_active:
                best = candidate
            elif candidate.is_active == best.is_active:
                if (candidate.expires_at or datetime.min.replace(tzinfo=timezone.utc)) > (
                    best.expires_at or datetime.min.replace(tzinfo=timezone.utc)
                ):
                    best = candidate

    return best
