from __future__ import annotations
from app.services.store.base import StoreVerifier


def _make_apple() -> StoreVerifier:
    from app.services.store.apple_verifier import AppleVerifier
    return AppleVerifier()


def _make_google() -> StoreVerifier:
    from app.services.store.google_play_verifier import GooglePlayVerifier
    return GooglePlayVerifier()


_REGISTRY: dict[str, type] = {
    "apple":  _make_apple,
    "google": _make_google,
}


class StoreVerifierFactory:
    @staticmethod
    def get(platform: str) -> StoreVerifier:
        factory_fn = _REGISTRY.get(platform)
        if factory_fn is None:
            raise ValueError(f"Desteklenmeyen store platform: {platform!r}")
        return factory_fn()
