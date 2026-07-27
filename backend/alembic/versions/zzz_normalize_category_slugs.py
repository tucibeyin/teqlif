"""Normalize legacy category slugs to canonical English keys

Revision ID: zzz_normalize_category_slugs
Revises: zz_hasar_vasita_all
Create Date: 2026-07-28

Eski nesil mock verilerinden kalan Türkçe/tirelı slug'ları
(spor-outdoor, giyim-aksesuar, ev-yasam, kitap-hobi) canonical
İngilizce slug'lara dönüştürür.

Etkilenen ilanlar (tespit edilen): 244
  giyim-aksesuar → fashion  (78 ilan)
  spor-outdoor   → sports   (67 ilan)
  ev-yasam       → home     (60 ilan)
  kitap-hobi     → books    (39 ilan)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "zzz_normalize_category_slugs"
down_revision: Union[str, Sequence[str], None] = "zz_hasar_vasita_all"
branch_labels = None
depends_on = None

# legacy_slug → canonical_slug
_SLUG_MAP = {
    "giyim-aksesuar": "fashion",
    "spor-outdoor":   "sports",
    "ev-yasam":       "home",
    "kitap-hobi":     "books",
}


def upgrade() -> None:
    conn = op.get_bind()
    for legacy, canonical in _SLUG_MAP.items():
        conn.execute(
            sa.text(
                "UPDATE listings SET category = :canonical "
                "WHERE category = :legacy"
            ),
            {"canonical": canonical, "legacy": legacy},
        )
    # categories tablosunda hâlâ kayıtlıysa pasife al (CategoryStatus enum: 'active' | 'passive')
    conn.execute(
        sa.text(
            "UPDATE categories SET status = 'passive' "
            "WHERE key = ANY(:keys)"
        ),
        {"keys": list(_SLUG_MAP.keys())},
    )


def downgrade() -> None:
    # Geri alma: canonical'dan legacy'ye — production'da kullanılmamalı.
    conn = op.get_bind()
    for legacy, canonical in _SLUG_MAP.items():
        conn.execute(
            sa.text(
                "UPDATE listings SET category = :legacy "
                "WHERE category = :canonical"
            ),
            {"canonical": canonical, "legacy": legacy},
        )
    conn.execute(
        sa.text(
            "UPDATE categories SET status = 'active' "
            "WHERE key = ANY(:keys)"
        ),
        {"keys": list(_SLUG_MAP.keys())},
    )
