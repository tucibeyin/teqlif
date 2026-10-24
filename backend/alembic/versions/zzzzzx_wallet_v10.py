"""Wallet V1.0: PRO abonelik, kazanc sistemi, ledger, cashout

Revision ID: zzzzzx_wallet_v10
Revises: zzzzzw_del_aiprice_transl
Create Date: 2026-10-24
"""
from __future__ import annotations
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from alembic import op

revision = 'zzzzzx_wallet_v10'
down_revision = 'zzzzzw_del_aiprice_transl'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. users — PRO abonelik kolonları ────────────────────────────────────
    op.add_column('users', sa.Column('pro_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('pro_grace_until', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('store_subscription_id', sa.String(128), nullable=True))
    op.add_column('users', sa.Column('store_subscription_platform', sa.String(20), nullable=True))
    op.create_index(
        'idx_users_pro_expires', 'users', ['user_type', 'pro_expires_at'],
        postgresql_where=sa.text("user_type = 'pro'"),
    )

    # ── 2. userstatus PostgreSQL enum — sistem kullanıcısı için 'inactive' ──
    # ALTER TYPE ... ADD VALUE transaction içinde kullanılamaz (PG kısıtı);
    # autocommit_block ile kendi transaction'ında çalıştırılır.
    # Downgrade'de enum value PG'de kalır (zararsız).
    with op.get_context().autocommit_block():
        op.execute(sa.text("ALTER TYPE userstatus ADD VALUE IF NOT EXISTS 'inactive'"))

    # ── 3. platform_config — tek yapılandırma deposu (Redis-cached) ──────────
    op.create_table(
        'platform_config',
        sa.Column('key', sa.String(60), nullable=False, primary_key=True),
        sa.Column('value', JSONB(), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
    )
    op.execute(
        "INSERT INTO platform_config (key, value, description) VALUES "
        "('teqlik_try_rate',     '{\"rate\": 0.50}',    '1 teqlik = kaç TRY (cashout dönüşüm kuru)'), "
        "('host_share_standard', '{\"pct\": 70}',        'Standart host hediye payı (%)'), "
        "('host_share_pro',      '{\"pct\": 95}',        'PRO host hediye payı (%)'), "
        "('iap_velocity_limit',  '{\"try\": 5000.00}',   'Cihaz başına günlük IAP limiti (TRY, Fail-Closed)'), "
        "('min_withdrawal_try',  '{\"try\": 500.00}',    'Minimum cashout tutarı (TRY karşılığı)'), "
        "('cashout_enabled',     '{\"enabled\": false}', 'Cashout özelliği aktif mi (OTA flag)')"
    )

    # ── 4. user_wallet_earnings — kazanç deposu (teqlik birimi) ──────────────
    op.create_table(
        'user_wallet_earnings',
        sa.Column('user_id', sa.Integer(),
                  sa.ForeignKey('users.id', ondelete='CASCADE'),
                  nullable=False, primary_key=True),
        sa.Column('pending', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('available', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
    )

    # ── 5. sistem kullanıcısı (id=0) — platform hazine hesabı ────────────────
    # SERIAL'da explicit id=0 INSERT sorunsuz; sequence 1'den başlar, çakışmaz.
    op.execute(
        "INSERT INTO users "
        "(id, email, username, full_name, hashed_password, status, "
        " email_verified, is_admin, teqlik_balance, token_version, locale) "
        "VALUES "
        "(0, 'system@teqlif.internal', 'system', 'Teqlif Platform', "
        " 'LOCKED_SYSTEM_ACCOUNT_NO_LOGIN', "
        " 'inactive', false, false, 0, 0, 'tr')"
    )

    # ── 6. wallet_ledger — append-only finansal denetim izi ──────────────────
    op.create_table(
        'wallet_ledger',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.Integer(),
                  sa.ForeignKey('users.id'), nullable=False),
        sa.Column('delta_teqlik', sa.Integer(), nullable=False),
        sa.Column('balance_after', sa.Integer(), nullable=False),
        sa.Column('try_equivalent', sa.Numeric(12, 4), nullable=True),
        sa.Column('try_rate_used', sa.Numeric(10, 6), nullable=True),
        sa.Column('tcmb_rate_used', sa.Numeric(10, 6), nullable=True),
        sa.Column('currency', sa.String(3), nullable=True),
        sa.Column('tx_type', sa.String(40), nullable=False),
        sa.Column('reference_id', sa.Integer(), nullable=True),
        sa.Column('reference_type', sa.String(30), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
    )
    op.create_index('idx_wallet_ledger_user_time', 'wallet_ledger',
                    ['user_id', 'created_at'])
    op.create_index('idx_wallet_ledger_type', 'wallet_ledger',
                    ['tx_type', 'created_at'])

    # ── 7. gift_events ALTER — kazanç teqlik birimi + T+14 payout durumu ─────
    op.add_column('gift_events',
                  sa.Column('earned_teqlik', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('gift_events',
                  sa.Column('host_share_pct', sa.Numeric(5, 2), nullable=False,
                            server_default='70.00'))
    op.add_column('gift_events',
                  sa.Column('payout_status', sa.String(20), nullable=False,
                            server_default="'pending'"))
    op.add_column('gift_events',
                  sa.Column('released_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index(
        'idx_gift_events_payout', 'gift_events', ['payout_status', 'sent_at'],
        postgresql_where=sa.text("payout_status = 'pending'"),
    )

    # ── 8. teqlik_transactions ALTER — store platform-agnostic ───────────────
    op.add_column('teqlik_transactions',
                  sa.Column('store_platform', sa.String(20), nullable=True))
    op.add_column('teqlik_transactions',
                  sa.Column('store_transaction_id', sa.String(128), nullable=True))
    op.add_column('teqlik_transactions',
                  sa.Column('raw_payload', sa.Text(), nullable=True))
    op.add_column('teqlik_transactions',
                  sa.Column('product_type', sa.String(20), nullable=False,
                            server_default="'consumable'"))
    op.create_index(
        'uq_store_tx', 'teqlik_transactions',
        ['store_platform', 'store_transaction_id'],
        unique=True,
        postgresql_where=sa.text('store_transaction_id IS NOT NULL'),
    )

    # ── 9. withdrawal_requests — cashout talepleri ────────────────────────────
    op.create_table(
        'withdrawal_requests',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.Integer(),
                  sa.ForeignKey('users.id'), nullable=False),
        sa.Column('teqlik_amount', sa.Integer(), nullable=False),
        sa.Column('try_amount', sa.Numeric(12, 2), nullable=False),
        sa.Column('currency', sa.String(3), nullable=False, server_default="'TRY'"),
        sa.Column('fiat_amount', sa.Numeric(12, 2), nullable=False),
        sa.Column('try_rate_used', sa.Numeric(10, 6), nullable=False),
        sa.Column('tcmb_rate_used', sa.Numeric(10, 6), nullable=True),
        sa.Column('iban', sa.String(34), nullable=False),
        sa.Column('account_holder', sa.String(120), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default="'pending'"),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('admin_note', sa.Text(), nullable=True),
    )
    op.create_index('idx_withdrawal_user', 'withdrawal_requests',
                    ['user_id', 'created_at'])
    op.create_index(
        'idx_withdrawal_pending', 'withdrawal_requests', ['status', 'created_at'],
        postgresql_where=sa.text("status = 'pending'"),
    )


def downgrade() -> None:
    op.drop_table('withdrawal_requests')

    op.drop_index('uq_store_tx', table_name='teqlik_transactions')
    op.drop_column('teqlik_transactions', 'product_type')
    op.drop_column('teqlik_transactions', 'raw_payload')
    op.drop_column('teqlik_transactions', 'store_transaction_id')
    op.drop_column('teqlik_transactions', 'store_platform')

    op.drop_index('idx_gift_events_payout', table_name='gift_events')
    op.drop_column('gift_events', 'released_at')
    op.drop_column('gift_events', 'payout_status')
    op.drop_column('gift_events', 'host_share_pct')
    op.drop_column('gift_events', 'earned_teqlik')

    op.drop_table('wallet_ledger')

    op.execute("DELETE FROM users WHERE id = 0")

    op.drop_table('user_wallet_earnings')
    op.drop_table('platform_config')

    op.drop_index('idx_users_pro_expires', table_name='users')
    op.drop_column('users', 'store_subscription_platform')
    op.drop_column('users', 'store_subscription_id')
    op.drop_column('users', 'pro_grace_until')
    op.drop_column('users', 'pro_expires_at')
    # userstatus 'inactive' değeri PG'de kalır — enum value kaldırmak
    # DROP TYPE + yeniden oluşturma gerektirir, mevcut satırlar etkilenmez.
