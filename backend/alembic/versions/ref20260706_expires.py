"""Add referral_code_expires_at to users, reset all existing referral codes

Revision ID: ref20260706_expires
Revises: z2a3b4c5d6e7
Create Date: 2026-07-06 17:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = 'ref20260706_expires'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade():
    # 1. Sütunu ekle
    op.add_column(
        'users',
        sa.Column('referral_code_expires_at', sa.DateTime(timezone=True), nullable=True)
    )

    # 2. Eski tüm kodları sıfırla — yeni sistem ilk istek geldiğinde taze kod üretecek
    op.execute("UPDATE users SET referral_code = NULL, referral_code_expires_at = NULL")


def downgrade():
    op.drop_column('users', 'referral_code_expires_at')
