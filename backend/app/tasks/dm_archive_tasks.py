"""DM metin mesajı arşiv görevi.

1 yıldan eski, her iki tarafça okunmuş metin mesajlarını:
  - Konuşma + yıl bazında gzip JSON olarak MinIO'ya yazar
    (teqlif/dm-archive/{user_a}_{user_b}/{year}.json.gz)
  - message_threads.has_archive = TRUE yapar
  - PG'den siler

Pazar 03:00 UTC'de çalışır; büyük çalışmalar için Telegram bildirir.
"""
from __future__ import annotations

import gzip
import json
import logging
from datetime import datetime, timezone

from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

_ARCHIVE_DAYS       = 365
_DM_ARCHIVE_PREFIX  = "dm-archive"
_BATCH_LIMIT        = 10_000   # tek seferde max işlenen mesaj
_NOTIFY_THRESHOLD   = 1_000


async def archive_old_dm_task(ctx: dict) -> None:
    """1 yıldan eski okunmuş metin DM'leri MinIO arşivine taşır."""
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        from app.services import storage_service as storage

        async with AsyncSessionLocal() as db:
            rows = await db.execute(text(f"""
                SELECT id, sender_id, receiver_id, content, created_at
                FROM direct_messages
                WHERE content_type = 'text'
                  AND is_read       = TRUE
                  AND is_hidden     = FALSE
                  AND created_at   < NOW() - INTERVAL '{_ARCHIVE_DAYS} days'
                ORDER BY created_at
                LIMIT {_BATCH_LIMIT}
            """))
            messages = rows.fetchall()

        if not messages:
            logger.info("archive_old_dm_task: arşivlenecek mesaj yok")
            return

        # Konuşma + yıl bazında grupla
        groups: dict[tuple[int, int, int], list[dict]] = {}
        for row in messages:
            msg_id, sender_id, receiver_id, content, created_at = row
            user_a = min(sender_id, receiver_id)
            user_b = max(sender_id, receiver_id)
            year = created_at.year
            key = (user_a, user_b, year)
            if key not in groups:
                groups[key] = []
            groups[key].append({
                "id":          msg_id,
                "sender_id":   sender_id,
                "receiver_id": receiver_id,
                "content":     content,
                "created_at":  created_at.isoformat(),
            })

        deleted_ids: list[int] = []
        archived_pairs: set[tuple[int, int]] = set()

        for (user_a, user_b, year), msgs in groups.items():
            object_key = f"{_DM_ARCHIVE_PREFIX}/{user_a}_{user_b}/{year}.json.gz"

            # Mevcut arşivi oku ve birleştir (aynı yıl birden fazla çalışma olursa)
            existing: list[dict] = []
            try:
                existing_bytes = await storage.get_object_bytes(object_key)
                if existing_bytes:
                    existing = json.loads(gzip.decompress(existing_bytes))
            except Exception:
                pass

            existing_ids = {m["id"] for m in existing}
            new_msgs = [m for m in msgs if m["id"] not in existing_ids]
            merged = existing + new_msgs
            merged.sort(key=lambda m: m["created_at"])

            payload = gzip.compress(json.dumps(merged, ensure_ascii=False).encode())
            await storage.upload_bytes(object_key, payload, content_type="application/gzip")

            deleted_ids.extend(m["id"] for m in new_msgs)
            archived_pairs.add((user_a, user_b))

        if not deleted_ids:
            return

        # PG'den sil (batch)
        async with AsyncSessionLocal() as db:
            await db.execute(text(
                f"DELETE FROM direct_messages WHERE id = ANY(:ids)"
            ), {"ids": deleted_ids})

            # has_archive flag'i set et
            for user_a, user_b in archived_pairs:
                await db.execute(text("""
                    UPDATE message_threads
                    SET has_archive = TRUE
                    WHERE user_a_id = :a AND user_b_id = :b
                """), {"a": user_a, "b": user_b})

            await db.commit()

        logger.info(
            "archive_old_dm_task: %d mesaj arşivlendi, %d konuşma işaretlendi",
            len(deleted_ids), len(archived_pairs),
        )

        if len(deleted_ids) >= _NOTIFY_THRESHOLD:
            logger.info(
                "archive_old_dm_task: büyük arşiv — %d mesaj, %d konuşma",
                len(deleted_ids), len(archived_pairs),
            )

    except Exception as exc:
        capture_exception(exc)
        logger.error("archive_old_dm_task hata: %s", exc)
        raise
