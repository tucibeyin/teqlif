"""Wallet V1.0b: pending_refund kolonu + refund_log tablosu

Revision ID: zzzzzx_wallet_v10b
Revises: zzzzzx_wallet_v10
Create Date: 2026-10-24
"""
from __future__ import annotations
import sqlalchemy as sa
from alembic import op

revision = 'zzzzzx_wallet_v10b'
down_revision = 'zzzzzx_wallet_v10'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # users.pending_refund — Apple iadesi sonrası bakiye < 0 ise admin inceleme bayrağı
    # ⚠️ CHECK (teqlik_balance >= 0) veya available >= 0 constraint'i OLMAMALI:
    #   webhook 500 → Apple 3 gün sonsuz retry döngüsü.
    op.add_column('users',
                  sa.Column('pending_refund', sa.Boolean(), nullable=False,
                            server_default='false'))

    # refund_log — tüm IAP iade olaylarının audit izi
    op.create_table(
        'refund_log',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.Integer(),
                  sa.ForeignKey('users.id'), nullable=False),
        sa.Column('store_platform', sa.String(20), nullable=False),
        sa.Column('store_transaction_id', sa.String(128), nullable=False),
        sa.Column('refunded_teqlik', sa.Integer(), nullable=False),
        sa.Column('original_teqlik', sa.Integer(), nullable=False),
        sa.Column('gift_teqlik_cancelled', sa.Integer(), nullable=False,
                  server_default='0'),
        sa.Column('balance_after', sa.Integer(), nullable=False),
        sa.Column('raw_payload', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
    )
    op.create_index('idx_refund_log_user', 'refund_log', ['user_id', 'created_at'])
    op.create_index('idx_refund_log_tx', 'refund_log',
                    ['store_platform', 'store_transaction_id'])


def downgrade() -> None:
    op.drop_table('refund_log')
    op.drop_column('users', 'pending_refund')
