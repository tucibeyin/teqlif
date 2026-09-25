"""D2/D4/D5 model düzeltmeleri

Revision ID: zzzzd_d2_d4_d5_model_fixes
Revises: zzzzc_listings_image_urls_jsonb
Create Date: 2026-09-25
"""
from alembic import op

revision = "zzzzd_d2_d4_d5_model_fixes"
down_revision = "zzzzc_listings_image_urls_jsonb"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # D2: listings.active_room_id → FK live_streams.id ON DELETE SET NULL
    op.execute(
        "UPDATE listings SET active_room_id = NULL "
        "WHERE active_room_id IS NOT NULL "
        "AND active_room_id NOT IN (SELECT id FROM live_streams)"
    )
    op.execute(
        "ALTER TABLE listings ADD CONSTRAINT fk_listings_active_room_id "
        "FOREIGN KEY (active_room_id) REFERENCES live_streams(id) ON DELETE SET NULL"
    )

    # D4: reports.created_at → TIMESTAMP WITH TIME ZONE + server default
    op.execute(
        "ALTER TABLE reports ALTER COLUMN created_at "
        "TYPE TIMESTAMP WITH TIME ZONE USING created_at AT TIME ZONE 'UTC'"
    )
    op.execute(
        "ALTER TABLE reports ALTER COLUMN created_at SET DEFAULT now()"
    )

    # D5: app_configs.updated_at → TIMESTAMP WITH TIME ZONE
    op.execute(
        "ALTER TABLE app_configs ALTER COLUMN updated_at "
        "TYPE TIMESTAMP WITH TIME ZONE USING updated_at AT TIME ZONE 'UTC'"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE listings DROP CONSTRAINT IF EXISTS fk_listings_active_room_id")
    op.execute(
        "ALTER TABLE reports ALTER COLUMN created_at "
        "TYPE TIMESTAMP WITHOUT TIME ZONE USING created_at AT TIME ZONE 'UTC'"
    )
    op.execute("ALTER TABLE reports ALTER COLUMN created_at SET DEFAULT now()")
    op.execute(
        "ALTER TABLE app_configs ALTER COLUMN updated_at "
        "TYPE TIMESTAMP WITHOUT TIME ZONE USING updated_at AT TIME ZONE 'UTC'"
    )
