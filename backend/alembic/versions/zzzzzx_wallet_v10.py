"""wallet v1.0: PRO sub + TL earnings + withdrawal_requests

Revision ID: zzzzzx_wallet_v10
Revises: zzzzzw_del_aiprice_transl
Create Date: 2026-10-24
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'zzzzzx_wallet_v10'
down_revision = 'zzzzzw_del_aiprice_transl'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── users: PRO abonelik alanları ─────────────────────────────────────────
    op.add_column('users', sa.Column('tl_earnings_balance', sa.Numeric(10, 2), nullable=False, server_default='0'))
    op.add_column('users', sa.Column('tl_pending_balance',  sa.Numeric(10, 2), nullable=False, server_default='0'))
    op.add_column('users', sa.Column('pro_expires_at',                sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('pro_grace_until',               sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('apple_original_transaction_id', sa.String(64),               nullable=True))

    # ── gift_events: TL hakediş takibi ───────────────────────────────────────
    op.add_column('gift_events', sa.Column('earnings_tl',  sa.Numeric(10, 4), nullable=False, server_default='0'))
    op.add_column('gift_events', sa.Column('payout_status', sa.String(20),    nullable=False, server_default="'pending'"))
    op.add_column('gift_events', sa.Column('released_at',  sa.DateTime(timezone=True), nullable=True))

    # ── teqlik_transactions: IAP takibi ──────────────────────────────────────
    op.add_column('teqlik_transactions', sa.Column('apple_transaction_id', sa.String(64), nullable=True))
    op.add_column('teqlik_transactions', sa.Column('raw_receipt',          sa.Text,       nullable=True))
    op.add_column('teqlik_transactions', sa.Column('product_type', sa.String(20), nullable=False, server_default="'consumable'"))
    op.create_unique_constraint('uq_teqlik_txn_apple_id', 'teqlik_transactions', ['apple_transaction_id'])

    # ── withdrawal_requests ───────────────────────────────────────────────────
    op.create_table(
        'withdrawal_requests',
        sa.Column('id',         sa.Integer,               primary_key=True),
        sa.Column('user_id',    sa.Integer,               sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('amount_tl',  sa.Numeric(10, 2),        nullable=False),
        sa.Column('iban',       sa.String(34),            nullable=False),
        sa.Column('status',     sa.String(20),            nullable=False, server_default='pending'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_withdrawal_requests_user', 'withdrawal_requests', ['user_id'])

    # ── İndeksler ─────────────────────────────────────────────────────────────
    op.create_index(
        'idx_users_pro_status', 'users', ['user_type', 'pro_expires_at'],
        postgresql_where=sa.text("user_type = 'pro'"),
    )
    op.create_index(
        'idx_gift_events_payout', 'gift_events', ['payout_status'],
        postgresql_where=sa.text("payout_status = 'pending'"),
    )


def downgrade() -> None:
    op.drop_index('idx_gift_events_payout',  table_name='gift_events')
    op.drop_index('idx_users_pro_status',    table_name='users')
    op.drop_table('withdrawal_requests')
    op.drop_constraint('uq_teqlik_txn_apple_id', 'teqlik_transactions', type_='unique')
    op.drop_column('teqlik_transactions', 'product_type')
    op.drop_column('teqlik_transactions', 'raw_receipt')
    op.drop_column('teqlik_transactions', 'apple_transaction_id')
    op.drop_column('gift_events', 'released_at')
    op.drop_column('gift_events', 'payout_status')
    op.drop_column('gift_events', 'earnings_tl')
    op.drop_column('users', 'apple_original_transaction_id')
    op.drop_column('users', 'pro_grace_until')
    op.drop_column('users', 'pro_expires_at')
    op.drop_column('users', 'tl_pending_balance')
    op.drop_column('users', 'tl_earnings_balance')
