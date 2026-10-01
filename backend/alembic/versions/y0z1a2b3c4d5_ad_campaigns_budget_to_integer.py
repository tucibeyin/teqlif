"""ad_campaigns budget columns: Float -> Integer (TUCi)

Revision ID: y0z1a2b3c4d5
Revises: x9y0z1a2b3c4
Create Date: 2026-06-24

"""
from alembic import op
import sqlalchemy as sa

revision = 'y0z1a2b3c4d5'
down_revision = 'x9y0z1a2b3c4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE ad_campaigns
            ALTER COLUMN total_budget TYPE INTEGER USING ROUND(total_budget)::INTEGER,
            ALTER COLUMN spent_budget TYPE INTEGER USING ROUND(spent_budget)::INTEGER,
            ALTER COLUMN cpc_bid      TYPE INTEGER USING ROUND(cpc_bid)::INTEGER
    """)


def downgrade() -> None:
    op.execute("""
        ALTER TABLE ad_campaigns
            ALTER COLUMN total_budget TYPE FLOAT USING total_budget::FLOAT,
            ALTER COLUMN spent_budget TYPE FLOAT USING spent_budget::FLOAT,
            ALTER COLUMN cpc_bid      TYPE FLOAT USING cpc_bid::FLOAT
    """)
