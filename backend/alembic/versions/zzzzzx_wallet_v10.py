"""Wallet V1.0: PRO abonelik, kazanc sistemi, ledger, cashout

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
    # ── 1. users — PRO abonelik kolonları (IF NOT EXISTS → idempotent) ───────
    op.execute(sa.text(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
        "pro_expires_at TIMESTAMP WITH TIME ZONE"
    ))
    op.execute(sa.text(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
        "pro_grace_until TIMESTAMP WITH TIME ZONE"
    ))
    op.execute(sa.text(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
        "store_subscription_id VARCHAR(128)"
    ))
    op.execute(sa.text(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
        "store_subscription_platform VARCHAR(20)"
    ))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS idx_users_pro_expires "
        "ON users (user_type, pro_expires_at) "
        "WHERE user_type = 'pro'"
    ))

    # ── 2. userstatus PostgreSQL enum — autocommit_block zorunlu (PG kısıtı) ─
    # Downgrade'de enum value PG'de kalır (zararsız).
    with op.get_context().autocommit_block():
        op.execute(sa.text(
            "ALTER TYPE userstatus ADD VALUE IF NOT EXISTS 'inactive'"
        ))

    # ── 3. platform_config — tek yapılandırma deposu (Redis-cached) ──────────
    op.execute(sa.text(
        "CREATE TABLE IF NOT EXISTS platform_config ("
        "  key         VARCHAR(60) NOT NULL PRIMARY KEY, "
        "  value       JSONB       NOT NULL, "
        "  description TEXT, "
        "  updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()"
        ")"
    ))
    op.execute(sa.text(
        "INSERT INTO platform_config (key, value, description) VALUES "
        "('teqlik_try_rate',     '{\"rate\": 0.50}',    '1 teqlik = kaç TRY (cashout dönüşüm kuru)'), "
        "('host_share_standard', '{\"pct\": 70}',        'Standart host hediye payı (%)'), "
        "('host_share_pro',      '{\"pct\": 95}',        'PRO host hediye payı (%)'), "
        "('iap_velocity_limit',  '{\"try\": 5000.00}',   'Cihaz başına günlük IAP limiti (TRY, Fail-Closed)'), "
        "('min_withdrawal_try',  '{\"try\": 500.00}',    'Minimum cashout tutarı (TRY karşılığı)'), "
        "('cashout_enabled',     '{\"enabled\": false}', 'Cashout özelliği aktif mi (OTA flag)') "
        "ON CONFLICT (key) DO NOTHING"
    ))

    # ── 4. user_wallet_earnings — kazanç deposu (teqlik birimi) ──────────────
    op.execute(sa.text(
        "CREATE TABLE IF NOT EXISTS user_wallet_earnings ("
        "  user_id    INTEGER NOT NULL PRIMARY KEY "
        "               REFERENCES users(id) ON DELETE CASCADE, "
        "  pending    INTEGER NOT NULL DEFAULT 0, "
        "  available  INTEGER NOT NULL DEFAULT 0, "
        "  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()"
        ")"
    ))

    # ── 5. sistem kullanıcısı (id=0) — platform hazine hesabı ────────────────
    # SERIAL'da explicit id=0 INSERT sorunsuz; sequence 1'den başlar, çakışmaz.
    op.execute(sa.text(
        "INSERT INTO users "
        "(id, email, username, full_name, hashed_password, status, "
        " email_verified, is_admin, is_shadowbanned, teqlik_balance, token_version, locale) "
        "VALUES "
        "(0, 'system@teqlif.internal', 'system', 'Teqlif Platform', "
        " 'LOCKED_SYSTEM_ACCOUNT_NO_LOGIN', "
        " 'inactive', false, false, false, 0, 0, 'tr') "
        "ON CONFLICT (id) DO NOTHING"
    ))

    # ── 6. wallet_ledger — append-only finansal denetim izi ──────────────────
    op.execute(sa.text(
        "CREATE TABLE IF NOT EXISTS wallet_ledger ("
        "  id             BIGSERIAL PRIMARY KEY, "
        "  user_id        INTEGER NOT NULL REFERENCES users(id), "
        "  delta_teqlik   INTEGER NOT NULL, "
        "  balance_after  INTEGER NOT NULL, "
        "  try_equivalent NUMERIC(12,4), "
        "  try_rate_used  NUMERIC(10,6), "
        "  tcmb_rate_used NUMERIC(10,6), "
        "  currency       VARCHAR(3), "
        "  tx_type        VARCHAR(40) NOT NULL, "
        "  reference_id   INTEGER, "
        "  reference_type VARCHAR(30), "
        "  created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()"
        ")"
    ))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS idx_wallet_ledger_user_time "
        "ON wallet_ledger (user_id, created_at)"
    ))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS idx_wallet_ledger_type "
        "ON wallet_ledger (tx_type, created_at)"
    ))

    # ── 7. gift_events ALTER — kazanç teqlik birimi + T+14 payout durumu ─────
    op.execute(sa.text(
        "ALTER TABLE gift_events ADD COLUMN IF NOT EXISTS "
        "earned_teqlik INTEGER NOT NULL DEFAULT 0"
    ))
    op.execute(sa.text(
        "ALTER TABLE gift_events ADD COLUMN IF NOT EXISTS "
        "host_share_pct NUMERIC(5,2) NOT NULL DEFAULT 70.00"
    ))
    op.execute(sa.text(
        "ALTER TABLE gift_events ADD COLUMN IF NOT EXISTS "
        "payout_status VARCHAR(20) NOT NULL DEFAULT 'pending'"
    ))
    op.execute(sa.text(
        "ALTER TABLE gift_events ADD COLUMN IF NOT EXISTS "
        "released_at TIMESTAMP WITH TIME ZONE"
    ))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS idx_gift_events_payout "
        "ON gift_events (payout_status, sent_at) "
        "WHERE payout_status = 'pending'"
    ))

    # ── 8. teqlik_transactions ALTER — store platform-agnostic ───────────────
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions ADD COLUMN IF NOT EXISTS "
        "store_platform VARCHAR(20)"
    ))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions ADD COLUMN IF NOT EXISTS "
        "store_transaction_id VARCHAR(128)"
    ))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions ADD COLUMN IF NOT EXISTS "
        "raw_payload TEXT"
    ))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions ADD COLUMN IF NOT EXISTS "
        "product_type VARCHAR(20) NOT NULL DEFAULT 'consumable'"
    ))
    op.execute(sa.text(
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_store_tx "
        "ON teqlik_transactions (store_platform, store_transaction_id) "
        "WHERE store_transaction_id IS NOT NULL"
    ))

    # ── 9. withdrawal_requests — cashout talepleri ────────────────────────────
    op.execute(sa.text(
        "CREATE TABLE IF NOT EXISTS withdrawal_requests ("
        "  id             SERIAL PRIMARY KEY, "
        "  user_id        INTEGER NOT NULL REFERENCES users(id), "
        "  teqlik_amount  INTEGER NOT NULL, "
        "  try_amount     NUMERIC(12,2) NOT NULL, "
        "  currency       VARCHAR(3) NOT NULL DEFAULT 'TRY', "
        "  fiat_amount    NUMERIC(12,2) NOT NULL, "
        "  try_rate_used  NUMERIC(10,6) NOT NULL, "
        "  tcmb_rate_used NUMERIC(10,6), "
        "  iban           VARCHAR(34) NOT NULL, "
        "  account_holder VARCHAR(120) NOT NULL, "
        "  status         VARCHAR(20) NOT NULL DEFAULT 'pending', "
        "  created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(), "
        "  processed_at   TIMESTAMP WITH TIME ZONE, "
        "  cancelled_at   TIMESTAMP WITH TIME ZONE, "
        "  admin_note     TEXT"
        ")"
    ))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS idx_withdrawal_user "
        "ON withdrawal_requests (user_id, created_at)"
    ))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS idx_withdrawal_pending "
        "ON withdrawal_requests (status, created_at) "
        "WHERE status = 'pending'"
    ))


def downgrade() -> None:
    op.execute(sa.text("DROP TABLE IF EXISTS withdrawal_requests"))

    op.execute(sa.text("DROP INDEX IF EXISTS uq_store_tx"))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions DROP COLUMN IF EXISTS product_type"
    ))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions DROP COLUMN IF EXISTS raw_payload"
    ))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions DROP COLUMN IF EXISTS store_transaction_id"
    ))
    op.execute(sa.text(
        "ALTER TABLE teqlik_transactions DROP COLUMN IF EXISTS store_platform"
    ))

    op.execute(sa.text("DROP INDEX IF EXISTS idx_gift_events_payout"))
    op.execute(sa.text(
        "ALTER TABLE gift_events DROP COLUMN IF EXISTS released_at"
    ))
    op.execute(sa.text(
        "ALTER TABLE gift_events DROP COLUMN IF EXISTS payout_status"
    ))
    op.execute(sa.text(
        "ALTER TABLE gift_events DROP COLUMN IF EXISTS host_share_pct"
    ))
    op.execute(sa.text(
        "ALTER TABLE gift_events DROP COLUMN IF EXISTS earned_teqlik"
    ))

    op.execute(sa.text("DROP TABLE IF EXISTS wallet_ledger"))
    op.execute(sa.text("DELETE FROM users WHERE id = 0"))
    op.execute(sa.text("DROP TABLE IF EXISTS user_wallet_earnings"))
    op.execute(sa.text("DROP TABLE IF EXISTS platform_config"))

    op.execute(sa.text("DROP INDEX IF EXISTS idx_users_pro_expires"))
    op.execute(sa.text(
        "ALTER TABLE users DROP COLUMN IF EXISTS store_subscription_platform"
    ))
    op.execute(sa.text(
        "ALTER TABLE users DROP COLUMN IF EXISTS store_subscription_id"
    ))
    op.execute(sa.text(
        "ALTER TABLE users DROP COLUMN IF EXISTS pro_grace_until"
    ))
    op.execute(sa.text(
        "ALTER TABLE users DROP COLUMN IF EXISTS pro_expires_at"
    ))
    # userstatus 'inactive' değeri PG'de kalır — enum value kaldırmak
    # DROP TYPE + yeniden oluşturma gerektirir, mevcut satırlar etkilenmez.
