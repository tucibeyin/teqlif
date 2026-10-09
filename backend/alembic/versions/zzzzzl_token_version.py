"""users: token_version kolonu

Logout ve şifre değişikliğinde tüm access token'ları anında geçersizleştirmek için.
JWT payload'a 'tv' claim eklendi; get_current_user bu değeri user.token_version ile karşılaştırır.
Mevcut tokenlar tv=0 içermediğinden geriye uyumlu: DEFAULT 0 ile eşleşir.

Revision ID: zzzzzl_token_version
Revises: zzzzzh_recording_host_notified
Create Date: 2026-10-09
"""
from alembic import op

revision = "zzzzzl_token_version"
down_revision = "zzzzzh_recording_host_notified"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE users "
        "ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS token_version")
