"""add referral system

Revision ID: a3b4c5d6e7f8
Revises: z2a3b4c5d6e7
Create Date: 2026-07-03 10:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'a3b4c5d6e7f8'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade():
    # ── 1. users tablosuna referral_code kolonu ekle ────────────────────────
    op.add_column('users', sa.Column('referral_code', sa.String(12), nullable=True))
    op.create_unique_constraint('uq_users_referral_code', 'users', ['referral_code'])
    op.create_index('ix_users_referral_code', 'users', ['referral_code'], unique=True)

    # ── 2. Mevcut kullanıcılar için benzersiz kod üret (backfill) ───────────
    # PostgreSQL'de SUBSTRING(MD5(RANDOM()::text || id::text), 1, 7) deterministik
    # değildir ama id bazlı MD5 kullanılır, çakışmaya karşı güvenlik için UPPER.
    # Karakter seti hex (0-9 A-F) — 7 hane → 16^7 = 268 milyon kombinasyon.
    op.execute("""
        UPDATE users
        SET referral_code = UPPER(SUBSTRING(MD5(id::text || 'teqlif_ref_2026'), 1, 7))
        WHERE referral_code IS NULL
    """)

    # Nadir çakışma ihtimaline karşı: aynı hash çıkabilir — sonraki tur düzeltir
    op.execute("""
        WITH dupes AS (
            SELECT id,
                   ROW_NUMBER() OVER (PARTITION BY referral_code ORDER BY id) AS rn
            FROM users
        )
        UPDATE users u
        SET referral_code = UPPER(SUBSTRING(MD5(u.id::text || 'teqlif_ref_v2_2026'), 1, 7))
        FROM dupes d
        WHERE u.id = d.id AND d.rn > 1
    """)

    # ── 3. referrals tablosunu oluştur ──────────────────────────────────────
    op.create_table(
        'referrals',
        sa.Column('id', sa.Integer(), primary_key=True, nullable=False),
        sa.Column('referrer_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('referred_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('status', sa.String(20), nullable=False, server_default='completed'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_referrals_referrer_id', 'referrals', ['referrer_id'])
    op.create_index('ix_referrals_referred_id', 'referrals', ['referred_id'])


def downgrade():
    op.drop_index('ix_referrals_referred_id', table_name='referrals')
    op.drop_index('ix_referrals_referrer_id', table_name='referrals')
    op.drop_table('referrals')

    op.drop_index('ix_users_referral_code', table_name='users')
    op.drop_constraint('uq_users_referral_code', 'users', type_='unique')
    op.drop_column('users', 'referral_code')
