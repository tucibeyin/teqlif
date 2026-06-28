"""add app_configs table

Revision ID: z2a3b4c5d6e7
Revises: z1a2b3c4d5e6
Create Date: 2026-06-28 10:57:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'z2a3b4c5d6e7'
down_revision = 'z1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'app_configs',
        sa.Column('key', sa.String(), nullable=False),
        sa.Column('value', sa.String(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('key')
    )
    op.create_index(op.f('ix_app_configs_key'), 'app_configs', ['key'], unique=False)
    
    # Varsayılan değerleri ekle
    op.execute("INSERT INTO app_configs (key, value, updated_at) VALUES ('ios_min_version', '1.0.0', NOW())")
    op.execute("INSERT INTO app_configs (key, value, updated_at) VALUES ('ios_latest_version', '1.0.0', NOW())")
    op.execute("INSERT INTO app_configs (key, value, updated_at) VALUES ('android_min_version', '1.0.0', NOW())")
    op.execute("INSERT INTO app_configs (key, value, updated_at) VALUES ('android_latest_version', '1.0.0', NOW())")


def downgrade():
    op.drop_index(op.f('ix_app_configs_key'), table_name='app_configs')
    op.drop_table('app_configs')

