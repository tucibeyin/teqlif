import posthog
from app.config import settings

_client: posthog.Posthog | None = None


def get_posthog() -> posthog.Posthog | None:
    """Returns the PostHog singleton, or None if API key is not configured."""
    global _client
    if _client is None and settings.posthog_api_key:
        _client = posthog.Posthog(
            project_api_key=settings.posthog_api_key,
            host=settings.posthog_host,
        )
    return _client


def capture(distinct_id: str | int, event: str, properties: dict | None = None) -> None:
    """Fire-and-forget PostHog event. Silently skips if client is not configured."""
    client = get_posthog()
    if client is None:
        return
    try:
        client.capture(
            distinct_id=str(distinct_id),
            event=event,
            properties=properties or {},
        )
    except Exception:
        pass
