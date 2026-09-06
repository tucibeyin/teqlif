# Mesaj & Konuşma Silme Planı

## Mevcut Sorunlar

| Eylem | Mevcut Davranış | Doğru Davranış |
|---|---|---|
| Gelen Kutusu → konuşmayı sil | İki taraf için hard delete | Sadece silen kişi için gizle |
| Mesaj üzerine uzun bas → sil | Sadece gönderen yapabilir, iki taraf için hard delete | "Benim için sil" / "Herkes için sil" seçeneği |

---

## 1. Konuşma Silme (Inbox Düzeyi)

### Backend — Alembic Migration

`message_threads` tablosuna iki nullable timestamp sütunu:

```sql
ALTER TABLE message_threads ADD COLUMN deleted_at_a TIMESTAMPTZ NULL;
ALTER TABLE message_threads ADD COLUMN deleted_at_b TIMESTAMPTZ NULL;
-- user_a_id = min(uid, other_id) → deleted_at_a
-- user_b_id = max(uid, other_id) → deleted_at_b
```

### DeleteConversationCommand

Hard delete kaldırılır. Kullanıcının tarafına `deleted_at_x = now()` set edilir.

```python
if uid == thread.user_a_id:
    thread.deleted_at_a = datetime.utcnow()
else:
    thread.deleted_at_b = datetime.utcnow()
```

### GetConversationsQuery

Silme kalıcıdır — `deleted_at_x` asla temizlenmez. Konuşma listesinde görünüm:

```python
# Hiç silmemiş VEYA silmiş ama sonrasında yeni mesaj var
WHERE (user_a_id == uid AND (deleted_at_a IS NULL OR last_message_at > deleted_at_a))
   OR (user_b_id == uid AND (deleted_at_b IS NULL OR last_message_at > deleted_at_b))
```

### GetMessagesQuery

Silme sonrası sadece `deleted_at_x`'ten sonraki mesajları göster — yeni mesaj gelince bile bu filtre değişmez:

```python
if uid == thread.user_a_id and thread.deleted_at_a:
    query = query.where(DirectMessage.created_at > thread.deleted_at_a)
elif uid == thread.user_b_id and thread.deleted_at_b:
    query = query.where(DirectMessage.created_at > thread.deleted_at_b)
```

> Silme kararı kalıcıdır. Silen kişi yeni mesaj atsa veya alsa da eski geçmişi görmez.

---

## 2. Mesaj Silme (Konuşma İçi)

### Backend — Alembic Migration

`direct_messages` tablosuna per-user silme flagleri:

```sql
ALTER TABLE direct_messages ADD COLUMN deleted_for_sender BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE direct_messages ADD COLUMN deleted_for_receiver BOOLEAN NOT NULL DEFAULT FALSE;
```

### API Değişikliği

```
DELETE /api/messages/{id}?scope=me|everyone
```

| scope | Kural | Davranış |
|---|---|---|
| `me` | Gönderen veya alıcı yapabilir | Kendi flag'ini `TRUE` yap, mesaj DB'de kalır |
| `everyone` | Sadece gönderen, gönderimden itibaren 48 saat içinde | Hard delete + WS `message_deleted` her ikisine |

### GetMessagesQuery

```python
# Gönderen için
WHERE NOT deleted_for_sender  (uid == sender_id)

# Alıcı için
WHERE NOT deleted_for_receiver  (uid == receiver_id)
```

### WS Olayları

| Eylem | WS |
|---|---|
| `scope=me` | Yok — sadece lokal UI güncellenir |
| `scope=everyone` | `message_deleted` event → her iki tarafa |

---

## 3. Mobile

### Konuşma Silme (Gelen Kutusu)

Mevcut uzun bas → sil akışı korunur. Backend değişikliği yeterli.

### Mesaj Silme (Konuşma İçi)

Uzun bas → bottom sheet:

```
┌─────────────────────────┐
│  Benim için sil         │  → scope=me  (herkes görebilir)
│  Herkes için sil        │  → scope=everyone (sadece gönderen)
└─────────────────────────┘
```

- "Herkes için sil" → sadece `sender_id == myUserId AND now - sentAt < 48h` ise göster
- UI'da silinen mesaj yerine: "Bu mesaj silindi" placeholder (scope=everyone) veya tamamen kaldır (scope=me)

---

## 4. Uygulama Sırası

1. Alembic migration (her iki tablo)
2. `DeleteConversationCommand` refactor
3. `GetConversationsQuery` filtresi
4. `GetMessagesQuery` filtresi + yeni mesaj gelince `deleted_at_x` temizleme
5. `DeleteMessageCommand` — scope parametresi + per-user flag
6. Mobile: bottom sheet + UI
