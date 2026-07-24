"""Add missing error localization keys: errorServerBusy, errorSessionExpired

Revision ID: aaa_error_loc_keys
Revises: zz_hasar_vasita_all
Create Date: 2026-07-24
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "aaa_error_loc_keys"
down_revision: Union[str, Sequence[str], None] = "zz_hasar_vasita_all"
branch_labels = None
depends_on = None

_ROWS = [
    ("errorServerBusy", "tr", "Sunucu şu an meşgul, lütfen daha sonra tekrar deneyin."),
    ("errorServerBusy", "en", "Server is busy, please try again later."),
    ("errorServerBusy", "ar", "الخادم مشغول حالياً، يرجى المحاولة لاحقاً."),
    ("errorServerBusy", "ru", "Сервер занят, попробуйте позже."),
    ("errorSessionExpired", "tr", "Oturumunuzun süresi doldu, lütfen tekrar giriş yapın."),
    ("errorSessionExpired", "en", "Your session has expired, please log in again."),
    ("errorSessionExpired", "ar", "انتهت جلستك، يرجى تسجيل الدخول مرة أخرى."),
    ("errorSessionExpired", "ru", "Ваш сеанс истёк, пожалуйста, войдите снова."),
]


def upgrade() -> None:
    conn = op.get_bind()
    for key, lang, value in _ROWS:
        conn.execute(
            sa.text(
                "INSERT INTO translations (key, lang, value) VALUES (:key, :lang, :value) "
                "ON CONFLICT (key, lang) DO UPDATE SET value = EXCLUDED.value"
            ),
            {"key": key, "lang": lang, "value": value},
        )


def downgrade() -> None:
    conn = op.get_bind()
    keys = list({r[0] for r in _ROWS})
    conn.execute(
        sa.text("DELETE FROM translations WHERE key = ANY(:keys)"),
        {"keys": keys},
    )
