# Notification Bug Fix — Implementation Plan

> **Hedef:** BUG-1, BUG-2, BUG-3'ü tek bir mimari düzeltmeyle çözmek
> **Referans matris:** `documents/notification/notification.md`
> **Yaklaşım:** `push_notification()` dokunulmaz; DM push'u ayrı `send_message_push()` fonksiyonuna taşınır

---

## Sorun Özeti

`message` tipi push'u `push_notification()` üzerinden geçiyor. Bu fonksiyon:
- Her çağrıda `notifications` tablosuna kayıt yazar (BUG-3)
- WS online kontrolü yapmaz (BUG-1)
- `list_notifications` endpoint'i `type` filtresi uygulamadığı için DM kayıtları Bildirimler sekmesine sızıyor (BUG-2)

Sosyal/pazar/sistem bildirimleri için bu davranış doğru. Yalnızca `message` için yanlış.

---

## Task 1 — `send_message_push()` fonksiyonu oluştur

**Dosya:** `backend/app/services/notification_service.py`

```python
async def send_message_push(
    receiver_id: int,
    sender_display_name: str,
    body: str,
    data: dict,
) -> None:
    """
    DM push: WS online ise gönderme, DB'ye yazmaz.
    """
    if await ws_manager.is_dm_online(receiver_id):
        return

    tokens = await _get_fcm_tokens(receiver_id)
    if not tokens:
        return

    await fcm_adapter.send_notification(
        tokens=tokens,
        title=sender_display_name,
        body=body,
        data={"type": "message", **data},
        is_silent=False,
    )
```

`is_dm_online(receiver_id)`: `ws_dm_online:{user_id}` Redis key'ini kontrol eder — zaten mevcut.

---

## Task 2 — `send_direct_message` servisinde push çağrısını değiştir

**Dosya:** `backend/app/services/send_direct_message.py` (veya ilgili service/use_case)

```python
# ÖNCE:
await push_notification(receiver_id, {
    "type": "message",
    "title": sender_name,
    "body": message_body,
    ...
})

# SONRA:
await send_message_push(
    receiver_id=receiver_id,
    sender_display_name=sender_name,
    body=message_body,
    data={"thread_id": thread_id, "sender_id": sender_id},
)
```

Auto-accepted senaryosu (initiator'a gönderilen push) da aynı şekilde değiştirilir.

---

## Task 3 — `list_notifications` endpoint filtresini düzelt

**Dosya:** `backend/app/routers/notifications.py`

```python
# ÖNCE (yaklaşık):
notifications = await db.execute(
    select(Notification)
    .where(Notification.user_id == current_user.id)
    .order_by(Notification.created_at.desc())
)

# SONRA:
notifications = await db.execute(
    select(Notification)
    .where(
        Notification.user_id == current_user.id,
        Notification.type != "message",       # ← eklenir
    )
    .order_by(Notification.created_at.desc())
)
```

`unread_count` endpoint'i zaten bu filtreyi uyguluyor — tutarlılık sağlanmış olur.

---

## Etkilenen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `backend/app/services/notification_service.py` | `send_message_push()` eklenir |
| `backend/app/services/send_direct_message.py` | push çağrısı → `send_message_push()` |
| `backend/app/routers/notifications.py` | `list_notifications`'a `type != "message"` filtresi |

**Dokunulmayan dosyalar:** `push_notification()`, FCM adapter, mobile taraf, badge hesaplama

---

## Beklenen Sonuç

| Bug | Çözüm |
|---|---|
| BUG-1 foreground banner | WS online ise push hiç gönderilmez → banner çıkmaz |
| BUG-2 Bildirimler listesi kirliliği | `type != "message"` filtresi → DM'ler listelenmez |
| BUG-3 gereksiz DB kaydı | `send_message_push()` DB'ye yazmaz |

---

## Task Takibi

- [ ] Task 1 — `send_message_push()` yaz
- [ ] Task 2 — `send_direct_message` push çağrısını değiştir
- [ ] Task 3 — `list_notifications` filtresini ekle
- [ ] Deploy & test
