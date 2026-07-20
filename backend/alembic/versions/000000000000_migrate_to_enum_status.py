"""migrate to enum status

Revision ID: 000000000000
Revises: 
Create Date: 2026-07-20 03:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '000000000000'
down_revision: Union[str, None] = 'zp_create_call_participants'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Create Enums
    op.execute("CREATE TYPE listingstatus AS ENUM ('active', 'passive', 'sold', 'suspended', 'expired', 'deleted');")
    op.execute("CREATE TYPE userstatus AS ENUM ('active', 'passive', 'banned', 'deleted');")
    op.execute("CREATE TYPE categorystatus AS ENUM ('active', 'passive');")
    op.execute("CREATE TYPE searchalertstatus AS ENUM ('active', 'passive');")

    # 2. Add Status Columns
    op.execute("ALTER TABLE listings ADD COLUMN status listingstatus DEFAULT 'active';")
    op.execute("ALTER TABLE users ADD COLUMN status userstatus DEFAULT 'active';")
    op.execute("ALTER TABLE categories ADD COLUMN status categorystatus DEFAULT 'active';")
    op.execute("ALTER TABLE search_alerts ADD COLUMN status searchalertstatus DEFAULT 'active';")

    # 3. Data Migration
    # -- LISTINGS --
    op.execute("UPDATE listings SET status = 'deleted' WHERE is_deleted = TRUE;")
    op.execute("UPDATE listings SET status = 'passive' WHERE is_deleted = FALSE AND is_active = FALSE;")
    op.execute("UPDATE listings SET status = 'active' WHERE is_deleted = FALSE AND is_active = TRUE;")
    
    # -- USERS --
    op.execute("UPDATE users SET status = 'deleted' WHERE deleted_at IS NOT NULL;")
    op.execute("UPDATE users SET status = 'passive' WHERE is_active = FALSE AND deleted_at IS NULL;")
    op.execute("UPDATE users SET status = 'active' WHERE is_active = TRUE AND deleted_at IS NULL;")
    
    # -- CATEGORIES & ALERTS --
    op.execute("UPDATE categories SET status = 'passive' WHERE is_active = FALSE;")
    op.execute("UPDATE categories SET status = 'active' WHERE is_active = TRUE;")
    
    op.execute("UPDATE search_alerts SET status = 'passive' WHERE is_active = FALSE;")
    op.execute("UPDATE search_alerts SET status = 'active' WHERE is_active = TRUE;")

    # 4. Drop Old Columns
    op.drop_column('listings', 'is_active')
    op.drop_column('listings', 'is_deleted')
    op.drop_column('users', 'is_active')
    op.drop_column('users', 'deleted_at')
    op.drop_column('categories', 'is_active')
    op.drop_column('search_alerts', 'is_active')

    # 5. Create Indices (The old ones that relied on is_active/is_deleted should be dropped and recreated)
    # Note: Alembic automatically handles dropping indices if they are bound to the column in some configs, 
    # but it's safer to drop them explicitly if they are named.
    op.execute("DROP INDEX IF EXISTS ix_listings_feed_organic;")
    op.execute("DROP INDEX IF EXISTS ix_listings_feed_recent;")
    op.execute("CREATE INDEX ix_listings_feed_organic ON listings (category, status, created_at DESC);")
    op.execute("CREATE INDEX ix_listings_feed_recent ON listings (status, created_at DESC);")
    
    op.execute("DROP INDEX IF EXISTS ix_search_alerts_user_active;")
    op.execute("CREATE INDEX ix_search_alerts_user_status ON search_alerts (user_id, status);")

def downgrade() -> None:
    # Reverse migrations
    op.add_column('search_alerts', sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('categories', sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('users', sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('listings', sa.Column('is_deleted', sa.Boolean(), server_default='false', nullable=False))
    op.add_column('listings', sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False))

    op.execute("UPDATE listings SET is_deleted = TRUE WHERE status = 'deleted';")
    op.execute("UPDATE listings SET is_active = FALSE WHERE status IN ('passive', 'suspended', 'expired', 'sold');")
    
    op.execute("UPDATE users SET deleted_at = NOW() WHERE status = 'deleted';")
    op.execute("UPDATE users SET is_active = FALSE WHERE status = 'passive';")

    op.execute("UPDATE categories SET is_active = FALSE WHERE status = 'passive';")
    op.execute("UPDATE search_alerts SET is_active = FALSE WHERE status = 'passive';")

    op.drop_column('search_alerts', 'status')
    op.drop_column('categories', 'status')
    op.drop_column('users', 'status')
    op.drop_column('listings', 'status')

    op.execute("DROP TYPE IF EXISTS searchalertstatus;")
    op.execute("DROP TYPE IF EXISTS categorystatus;")
    op.execute("DROP TYPE IF EXISTS userstatus;")
    op.execute("DROP TYPE IF EXISTS listingstatus;")
