"""add story_views table

Revision ID: g2h3i4j5k6l7
Revises: f1a2b3c4d5e6
Create Date: 2026-03-27

"""
from alembic import op

revision = 'g2h3i4j5k6l7'
down_revision = 'f1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS story_views (
            id          SERIAL PRIMARY KEY,
            story_id    INTEGER NOT NULL
                            REFERENCES stories(id) ON DELETE CASCADE,
            viewer_id   INTEGER NOT NULL
                            REFERENCES users(id) ON DELETE CASCADE,
            viewed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT  uq_story_viewer UNIQUE (story_id, viewer_id)
        )
    """)
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_story_views_story_id  ON story_views(story_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_story_views_viewer_id ON story_views(viewer_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_story_views_viewed_at ON story_views(viewed_at)"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS story_views")
