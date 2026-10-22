"""Remove ai_price translation keys from DB

Revision ID: zzzzzw_del_aiprice_transl
Revises: zzzzzv_v18_user_type
Create Date: 2026-10-22
"""
from __future__ import annotations
from alembic import op

revision = 'zzzzzw_del_aiprice_transl'
down_revision = 'zzzzzv_v18_user_type'
branch_labels = None
depends_on = None

_AI_PRICE_KEYS = (
    'aiPriceAnalyzing',
    'aiPriceApply',
    'aiPriceButton',
    'aiPriceError',
    'aiPriceSimilar',
    'aiPriceTitle',
    'proToolAiPriceDesc',
    'proToolAiPriceTitle',
    'walletTxnSpendAiPrice',
)


def upgrade() -> None:
    keys = ', '.join(f"'{k}'" for k in _AI_PRICE_KEYS)
    op.execute(f"DELETE FROM translations WHERE key IN ({keys})")


def downgrade() -> None:
    pass
