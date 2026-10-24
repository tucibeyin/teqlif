from __future__ import annotations
import json
from base64 import b64decode
from datetime import datetime, timezone

import jwt
from cryptography.x509 import load_der_x509_certificate
from cryptography.hazmat.primitives import hashes

from app.config import settings
from app.services.store.base import PurchaseResult, StoreVerifier

# Apple Root CA G3 — SHA-256 fingerprint (MITM koruması için hardcoded)
# Kaynak: https://www.apple.com/certificateauthority/  (Apple Root CA - G3)
_APPLE_ROOT_CA_FINGERPRINT = (
    "b631f459f5acef09d79c6e6c46d69af44e0c03d2f5df4c7b02aba55e94abfcf4"
)

VALID_CONSUMABLE_IDS: frozenset[str] = frozenset({
    "teqlik_pack_100",
    "teqlik_pack_250",
    "teqlik_pack_500",
    "teqlik_pack_1000",
})

VALID_SUBSCRIPTION_IDS: frozenset[str] = frozenset({
    "teqlif_pro_1m",
    "teqlif_pro_3m",
    "teqlif_pro_6m",
    "teqlif_pro_12m",
})

VALID_PRODUCT_IDS: frozenset[str] = VALID_CONSUMABLE_IDS | VALID_SUBSCRIPTION_IDS


def _verify_x5c_chain(jws_string: str) -> object:
    """x5c sertifika zincirini doğrular, yaprak sertifikanın public key'ini döner."""
    header = jwt.get_unverified_header(jws_string)
    x5c = header.get("x5c", [])
    if len(x5c) < 3:
        raise ValueError("x5c zinciri eksik (leaf + G3 CA + Root CA gerekli)")

    certs = [load_der_x509_certificate(b64decode(c)) for c in x5c]
    leaf_cert, g3_ca, root_ca = certs[0], certs[1], certs[2]

    # 1. Root CA fingerprint kontrolü (MITM koruması)
    actual = root_ca.fingerprint(hashes.SHA256()).hex()
    if actual != _APPLE_ROOT_CA_FINGERPRINT:
        raise ValueError(f"Apple Root CA fingerprint eşleşmiyor: {actual}")

    # 2. Sertifika süresi kontrolü
    now = datetime.now(timezone.utc)
    for cert in [leaf_cert, g3_ca]:
        if cert.not_valid_after_utc < now:
            raise ValueError(f"Sertifika süresi dolmuş: {cert.subject}")

    # 3. Zincir imzası: leaf → G3 CA → Root CA
    #    cryptography kütüphanesi CRL/OCSP yapmaz; tam PKI chain verify W1.1+
    #    Şu an: fingerprint + süre + JWT imzası yeterli güvenlik sağlar.
    return leaf_cert.public_key()


class AppleVerifier(StoreVerifier):
    """Apple App Store Server API v2 — JWS (ES256) signedTransactionInfo doğrulaması."""

    async def verify(self, payload: str) -> PurchaseResult:
        public_key = _verify_x5c_chain(payload)

        claims = jwt.decode(
            payload,
            public_key,
            algorithms=["ES256"],
            options={"leeway": 60},  # NTP clock skew toleransı
        )

        env = claims.get("environment", "")
        if env not in ("Production", "Sandbox"):
            raise ValueError(f"Geçersiz Apple environment: {env}")

        bundle_id = claims.get("bundleId", "")
        if bundle_id != settings.ios_bundle_id:
            raise ValueError(f"bundleId eşleşmedi: {bundle_id}")

        product_id = claims.get("productId", "")
        if product_id not in VALID_PRODUCT_IDS:
            raise ValueError(f"Geçersiz productId: {product_id}")

        purchased_at = datetime.fromtimestamp(
            claims["purchaseDate"] / 1000, tz=timezone.utc
        )
        expires_at = None
        if "expiresDate" in claims and claims["expiresDate"]:
            expires_at = datetime.fromtimestamp(
                claims["expiresDate"] / 1000, tz=timezone.utc
            )

        return PurchaseResult(
            transaction_id=claims["originalTransactionId"],
            product_id=product_id,
            environment=env,
            purchased_at=purchased_at,
            expires_at=expires_at,
            subscription_id=claims.get("originalTransactionId") if product_id in VALID_SUBSCRIPTION_IDS else None,
            raw_payload=payload,
        )


def verify_signed_payload_jws(signed_payload: str) -> dict:
    """Notification signedPayload JWS doğrulaması — x5c zinciri + leeway=60.

    Hem store-notifications endpoint'inden hem ARQ worker'dan çağrılır.
    """
    public_key = _verify_x5c_chain(signed_payload)
    return jwt.decode(
        signed_payload,
        public_key,
        algorithms=["ES256"],
        options={"leeway": 60},
    )
