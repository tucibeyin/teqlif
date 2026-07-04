"""rename is_verified to email_verified

Revision ID: a3b4c5d6e7f8
Revises: z2a3b4c5d6e7
Create Date: 2026-07-04

is_verified sadece e-posta doğrulamasını temsil ediyordu; bu isim "tam doğrulama"
gibi görünüp kafa karışıklığına yol açıyordu.
email_verified → yalnızca e-posta doğrulandı
phone_verified → yalnızca telefon doğrulandı
is_verified → model property: email_verified AND phone_verified (tam doğrulama)
"""
from alembic import op

revision = 'b9c0d1e2f3a4'
down_revision = 'z2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('users', 'is_verified', new_column_name='email_verified')


def downgrade() -> None:
    op.alter_column('users', 'email_verified', new_column_name='is_verified')
