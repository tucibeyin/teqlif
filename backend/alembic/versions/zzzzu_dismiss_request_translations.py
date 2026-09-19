"""add dismiss message request translation strings

Revision ID: zzzzu_dismiss_req_i18n
Revises: zzzzt_remove_visual_emb
Create Date: 2026-09-19 10:00:00.000000

"""
import sqlalchemy as sa
from alembic import op

revision = 'zzzzu_dismiss_req_i18n'
down_revision = 'zzzzt_remove_visual_emb'
branch_labels = None
depends_on = None

_KEYS = {
    'msgDismissRequest': {
        'tr': 'İsteği Sil',
        'en': 'Delete Request',
        'ar': 'حذف الطلب',
        'ru': 'Удалить запрос',
    },
    'msgDismissRequestConfirm': {
        'tr': 'Bu mesaj isteğini silmek istediğine emin misin? Karşı taraf tekrar mesaj isteği gönderebilir.',
        'en': 'Are you sure you want to delete this message request? The sender can request again.',
        'ar': 'هل أنت متأكد أنك تريد حذف طلب الرسالة هذا؟ يمكن للمرسل إرسال طلب مرة أخرى.',
        'ru': 'Вы уверены, что хотите удалить этот запрос? Отправитель сможет отправить его снова.',
    },
    'msgDismissRequestSuccess': {
        'tr': 'Mesaj isteği silindi',
        'en': 'Message request deleted',
        'ar': 'تم حذف طلب الرسالة',
        'ru': 'Запрос на сообщение удалён',
    },
    'msgDismissRequestFailed': {
        'tr': 'İstek silinemedi',
        'en': 'Failed to delete request',
        'ar': 'تعذّر حذف الطلب',
        'ru': 'Не удалось удалить запрос',
    },
}


def upgrade() -> None:
    rows = [
        {"key": key, "lang": lang, "value": value}
        for key, langs in _KEYS.items()
        for lang, value in langs.items()
    ]
    op.get_bind().execute(
        sa.text(
            "INSERT INTO translations (key, lang, value) VALUES (:key, :lang, :value) "
            "ON CONFLICT (key, lang) DO UPDATE SET value = EXCLUDED.value"
        ),
        rows,
    )


def downgrade() -> None:
    keys = list(_KEYS.keys())
    op.get_bind().execute(
        sa.text("DELETE FROM translations WHERE key = ANY(:keys)"),
        {"keys": keys},
    )
