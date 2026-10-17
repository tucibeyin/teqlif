"""agent_delete_grant: teqlif_agent DELETE yetkisi

Revision ID: zzzzzr_agent_delete_grant
Revises: zzzzzq_teqlik_balance_500
Create Date: 2026-10-17
"""
from alembic import op

revision = "zzzzzr_agent_delete_grant"
down_revision = "zzzzzq_teqlik_balance_500"
branch_labels = None
depends_on = None

_TABLES = [
    "notifications", "stories", "analytics_events",
    "user_interactions", "listing_offers", "live_stream_viewers",
    "exchange_rates", "search_alerts", "message_threads",
    "listing_impressions", "stream_recordings", "live_streams",
]


def upgrade() -> None:
    tables = ", ".join(_TABLES)
    op.execute(f"GRANT DELETE ON {tables} TO teqlif_agent")


def downgrade() -> None:
    tables = ", ".join(_TABLES)
    op.execute(f"REVOKE DELETE ON {tables} FROM teqlif_agent")
