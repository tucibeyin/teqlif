"""reserved_usernames tablosu — belirli kullanıcı adlarını kayıt akışından korur

Revision ID: zzzzzzzf_reserved_usernames
Revises: zzzzzze_user_devices
Create Date: 2026-11-19
"""
from alembic import op

revision = "zzzzzzzf_reserved_usernames"
down_revision = "zzzzzze_user_devices"
branch_labels = None
depends_on = None

_SEED = [
    # Marka / sistem
    ("teqlif",         "brand",  None),
    ("admin",          "system", None),
    ("administrator",  "system", None),
    ("system",         "system", None),
    ("root",           "system", None),
    # Destek
    ("support",        "brand",  None),
    ("destek",         "brand",  None),
    ("help",           "brand",  None),
    ("yardim",         "brand",  None),
    ("info",           "brand",  None),
    ("iletisim",       "brand",  None),
    # Teknik
    ("api",            "system", None),
    ("app",            "system", None),
    ("www",            "system", None),
    ("mail",           "system", None),
    ("bot",            "system", None),
    ("server",         "system", None),
    # Moderasyon
    ("moderator",      "brand",  None),
    ("mod",            "brand",  None),
    ("official",       "brand",  None),
    ("resmi",          "brand",  None),
    # Kişiye özel
    ("mert",           "person", "reserved for future assignment"),
]


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS reserved_usernames (
            id           SERIAL PRIMARY KEY,
            username     VARCHAR(50)  NOT NULL UNIQUE,
            reason       VARCHAR(20)  NOT NULL DEFAULT 'brand',
            note         TEXT,
            reserved_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_reserved_usernames_username ON reserved_usernames (username)")

    for username, reason, note in _SEED:
        note_sql = f"'{note}'" if note else "NULL"
        op.execute(f"""
            INSERT INTO reserved_usernames (username, reason, note)
            VALUES ('{username}', '{reason}', {note_sql})
            ON CONFLICT (username) DO NOTHING
        """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS reserved_usernames")
