"""Wallet V1.0: store IAP, kazanc sistemi, PRO abonelik

Revision ID: zzzzzx_wallet_v10
Revises: zzzzzw_del_aiprice_transl
Create Date: 2026-10-24
"""
from alembic import op
import sqlalchemy as sa

revision = 'zzzzzx_wallet_v10'
down_revision = 'zzzzzw_del_aiprice_transl'
branch_labels = None
depends_on = None


def upgrade():
    # ── users: TL kazanc bakiyeleri ──────────────────────────────────────────
    # CHECK (>= 0) intentionally omitted: Apple refund can push balance negative;
    # a DB constraint would cause webhook 500 → Apple infinite retry storm.
    op.add_column('users', sa.Column(
        'tl_earnings_balance', sa.Numeric(10, 2), nullable=False, server_default='0.00'
    ))
    op.add_column('users', sa.Column(
        'tl_pending_balance', sa.Numeric(10, 2), nullable=False, server_default='0.00'
    ))

    # ── users: PRO abonelik kolonlari ─────────────────────────────────────────
    op.add_column('users', sa.Column(
        'pro_expires_at', sa.DateTime(timezone=True), nullable=True
    ))
    op.add_column('users', sa.Column(
        'pro_grace_until', sa.DateTime(timezone=True), nullable=True
    ))
    op.add_column('users', sa.Column(
        'store_subscription_id', sa.String(128), nullable=True
    ))
    op.add_column('users', sa.Column(
        'store_subscription_platform', sa.String(20), nullable=True
    ))
    op.create_index(
        'idx_users_pro_status',
        'users',
        ['user_type', 'pro_expires_at'],
        postgresql_where=sa.text("user_type = 'pro'")
    )

    # ── gift_events: hakEdis sistemi ─────────────────────────────────────────
    op.add_column('gift_events', sa.Column(
        'earnings_tl', sa.Numeric(10, 4), nullable=False, server_default='0.0000'
    ))
    op.add_column('gift_events', sa.Column(
        'payout_status', sa.String(20), nullable=False, server_default='pending'
    ))
    op.add_column('gift_events', sa.Column(
        'released_at', sa.DateTime(timezone=True), nullable=True
    ))
    op.create_index(
        'idx_gift_events_payout',
        'gift_events',
        ['payout_status', 'sent_at'],
        postgresql_where=sa.text("payout_status = 'pending'")
    )

    # ── teqlik_transactions: store IAP kolonlari ──────────────────────────────
    op.add_column('teqlik_transactions', sa.Column(
        'store_transaction_id', sa.String(128), nullable=True
    ))
    op.add_column('teqlik_transactions', sa.Column(
        'store_platform', sa.String(20), nullable=True
    ))
    op.add_column('teqlik_transactions', sa.Column(
        'raw_payload', sa.Text(), nullable=True
    ))
    op.add_column('teqlik_transactions', sa.Column(
        'product_type', sa.String(20), nullable=False, server_default='consumable'
    ))
    # Composite partial unique: platform + transaction_id (replay koruması)
    # Non-store islemler (airdrop, convert) NULL birakar — partial WHERE disinda kalir
    # Apple/Google/Web ID'leri cakisabileceginden global UNIQUE yerine platform-scoped
    op.create_index(
        'uq_store_platform_tx',
        'teqlik_transactions',
        ['store_platform', 'store_transaction_id'],
        unique=True,
        postgresql_where=sa.text("store_transaction_id IS NOT NULL")
    )

    # ── withdrawal_requests: cekim talepleri ─────────────────────────────────
    op.create_table(
        'withdrawal_requests',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('amount_tl', sa.Numeric(10, 2), nullable=False),
        sa.Column('iban', sa.String(34), nullable=False),
        sa.Column('account_holder', sa.String(120), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('admin_note', sa.Text(), nullable=True),
    )


def downgrade():
    op.drop_table('withdrawal_requests')
    op.drop_index('uq_store_platform_tx', table_name='teqlik_transactions')
    op.drop_column('teqlik_transactions', 'product_type')
    op.drop_column('teqlik_transactions', 'raw_payload')
    op.drop_column('teqlik_transactions', 'store_platform')
    op.drop_column('teqlik_transactions', 'store_transaction_id')
    op.drop_index('idx_gift_events_payout', table_name='gift_events')
    op.drop_column('gift_events', 'released_at')
    op.drop_column('gift_events', 'payout_status')
    op.drop_column('gift_events', 'earnings_tl')
    op.drop_index('idx_users_pro_status', table_name='users')
    op.drop_column('users', 'store_subscription_platform')
    op.drop_column('users', 'store_subscription_id')
    op.drop_column('users', 'pro_grace_until')
    op.drop_column('users', 'pro_expires_at')
    op.drop_column('users', 'tl_pending_balance')
    op.drop_column('users', 'tl_earnings_balance')
