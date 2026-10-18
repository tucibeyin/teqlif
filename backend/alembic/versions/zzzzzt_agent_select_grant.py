"""agent_select_grant: teqlif_agent SELECT yetkisi

DELETE ... WHERE koşulundaki kolon değerlerine erişmek için SELECT
gereklidir (PostgreSQL docs). Cleaner'ın WHERE sorgularını çalıştırabilmesi
için eksik SELECT grant'ları ekleniyor.

Revision ID: zzzzzt_agent_select_grant
Revises: zzzzzr_agent_delete_grant
Create Date: 2026-10-18
"""
from alembic import op

revision = "zzzzzt_agent_select_grant"
down_revision = "zzzzzr_agent_delete_grant"
branch_labels = None
depends_on = None

_TABLES = [
    "notifications", "stories", "analytics_events",
    "user_interactions", "listing_offers", "live_stream_viewers",
    "exchange_rates", "search_alerts", "message_threads",
    "listing_impressions",
]


def upgrade() -> None:
    tables = ", ".join(_TABLES)
    op.execute(f"GRANT SELECT ON {tables} TO teqlif_agent")


def downgrade() -> None:
    tables = ", ".join(_TABLES)
    op.execute(f"REVOKE SELECT ON {tables} FROM teqlif_agent")
