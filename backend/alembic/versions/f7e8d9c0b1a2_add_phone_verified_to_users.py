"""add phone_verified to users

Revision ID: a1b2c3d4e5f6
Revises: z1a2b3c4d5e6
Create Date: 2026-06-27

"""
from alembic import op
import sqlalchemy as sa

revision = 'f7e8d9c0b1a2'
down_revision = 'b0f17a2ff415'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('phone_verified', sa.Boolean(), nullable=False, server_default='false'))
    # Mevcut telefon numarası olan kullanıcılar zaten doğrulanmış sayılır
    op.execute("UPDATE users SET phone_verified = true WHERE phone IS NOT NULL")


def downgrade() -> None:
    op.drop_column('users', 'phone_verified')
