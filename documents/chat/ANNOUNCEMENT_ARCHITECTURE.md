# Chat Duyuru Mimarisi

Son güncelleme: 2026-08-08

---

## Motivasyon

Auction kazananı, BIN (Hemen Al) kabulü ve DS satın alımları chat'te duyurulmaktadır.
Mevcut yapıda bu duyurular `WS.MESSAGE` tipiyle ham emoji string olarak gönderilmekte;
Flutter tarafından sıradan kullanıcı mesajından ayırt edilememekte, Türkçe hardcoded
ve i18n desteksizdir.

Bu belge, tüm sistem duyurularını tek bir mekanizma üzerinden yöneten, ileriye dönük
genişlemeye açık temiz bir mimariyi tanımlar.

---

## Mevcut Durum (Refactor Öncesi)

```python
# auction_commands.py — accept_bid ve BIN accepted
chat_msg = {
    "type": WS.MESSAGE,
    "username": buyer_username,
    "content": "🛒 Hemen Alındı! 📦 iPhone — 45₺ — 🏅 @ali",
    ...
}
await publish_chat(stream_id, chat_msg)
```

**Sorunlar:**
- `WS.MESSAGE` tipi → Flutter kullanıcı mesajından ayırt edemiyor
- İçerik Türkçe hardcoded → i18n yok
- Yapılandırılmamış string → Flutter parse edemez, özel UI uygulanamaz
- Her yeni duyuru tipi için ayrı kod yazmak gerekiyor

---

## Hedef Mimari

### Pattern: Typed Event + Strategy Renderer

Backend tek bir `chat_announcement()` helper'ı üretir.
Flutter `announcementType` değerine göre doğru tile'ı seçer.
Yeni duyuru tipi eklemek: backend'de 1 çağrı + Flutter'da 1 switch case.

---

## Backend

### 1. Yeni WS sabiti

`backend/app/constants/ws_types.py`:
```python
ANNOUNCEMENT = "announcement"   # sistem duyuruları için ayrı tip
```

### 2. `chat_announcement()` helper — `chat_utils.py`

```python
async def chat_announcement(
    stream_id: int,
    announcement_type: str,
    payload: dict,
    *,
    persist: bool = True,
) -> None:
    """Tüm sistem duyurularının tek giriş noktası."""
    msg = {
        "type": WS.ANNOUNCEMENT,
        "id": str(uuid.uuid4())[:8],
        "announcement_type": announcement_type,
        "payload": payload,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    if persist:
        redis = await get_redis()
        await redis.rpush(chat_key(stream_id), json.dumps(msg))
        await redis.ltrim(chat_key(stream_id), -50, -1)
        await redis.expire(chat_key(stream_id), 24 * 3600)
    await publish_chat(stream_id, msg)
```

### 3. Duyuru tipleri ve payload şemaları

| `announcement_type` | Tetikleyen yer | Payload alanları |
|---|---|---|
| `auction_winner` | `accept_bid` | `winner`, `price`, `item` |
| `bin_accepted` | BIN kabul | `buyer`, `price`, `item`, `listing_id?` |
| `ds_purchase` | DS satın alım | `buyer`, `price`, `item`, `remaining` |
| *(gelecek)* | — | — |

### 4. Mevcut çağrılar → `chat_announcement`'a geçiş

```python
# accept_bid (auction kazananı)
await chat_announcement(stream_id, "auction_winner", {
    "winner": winner_name,
    "price": final_price,
    "item": item_name,
})

# BIN accepted
await chat_announcement(stream_id, "bin_accepted", {
    "buyer": buyer_username,
    "item": item_name,
    "price": bin_price,
    "listing_id": listing_id,  # opsiyonel, ilan linki için
})

# DS satın alım (yeni)
await chat_announcement(stream_id, "ds_purchase", {
    "buyer": buyer_username,
    "item": item_name,
    "price": unit_price,
    "remaining": remaining_stock,
})
```

### 5. DS Rate-limiting (client-side tercih edildi)

DS alımları kısa aralıklarla gelebilir (örn. 10 stok → 10 alıcı, 30 saniyede).
Server-side Redis penceresi karmaşıklık ekler; bunun yerine Flutter tarafında
**client-side batching** uygulanır:

- 3–4 saniyelik pencere içinde gelen `ds_purchase` eventleri birleştirilir
- Son duyuru mesajı in-place güncellenir: `"Ali satın aldı"` → `"Ali, Zeynep ve 3 kişi daha satın aldı"`
- Chat listesi rebuild yerine son item update edilir

---

## Flutter

### 1. Discriminated Union — `ChatItem`

`mobile/lib/models/chat_message.dart`:

```dart
sealed class ChatItem {
  const ChatItem();
}

class UserMessage extends ChatItem {
  final String id;
  final String username;
  final String content;
  final String? avatarUrl;
  final String? url;
  final DateTime createdAt;
  const UserMessage({...});
}

class SystemAnnouncement extends ChatItem {
  final String id;
  final String announcementType;   // "auction_winner" | "bin_accepted" | "ds_purchase" | ...
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  const SystemAnnouncement({...});
}
```

### 2. Chat listesi — switch dispatch

```dart
ListView.builder(
  itemBuilder: (ctx, i) => switch (items[i]) {
    UserMessage m      => UserMessageTile(m),
    SystemAnnouncement a => AnnouncementTile(a),
  },
)
```

### 3. `AnnouncementTile` — Strategy Renderer

Her `announcementType` farklı ikon, renk ve i18n şablonu alır:

```dart
class AnnouncementTile extends StatelessWidget {
  const AnnouncementTile(this.announcement);
  final SystemAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final loc = ...; // localizationProvider
    return switch (announcement.announcementType) {
      "auction_winner" => _buildChip(
          icon: Icons.emoji_events_rounded,
          color: Colors.amber,
          text: loc.t("announcementAuctionWinner", {
            "winner": announcement.payload["winner"],
            "price": _fmt(announcement.payload["price"]),
          }),
        ),
      "bin_accepted"   => _buildChip(
          icon: Icons.shopping_cart_rounded,
          color: Colors.blue,
          text: loc.t("announcementBinAccepted", {
            "buyer": announcement.payload["buyer"],
            "price": _fmt(announcement.payload["price"]),
          }),
        ),
      "ds_purchase"    => _buildChip(
          icon: Icons.shopping_bag_rounded,
          color: Colors.green,
          text: loc.t("announcementDsPurchase", {
            "buyer": announcement.payload["buyer"],
            "remaining": announcement.payload["remaining"].toString(),
          }),
        ),
      _                => _buildChip(
          icon: Icons.info_outline_rounded,
          color: Colors.white54,
          text: announcement.payload["message"] ?? "—",
        ),
    };
  }

  Widget _buildChip({required IconData icon, required Color color, required String text}) { ... }
}
```

### 4. DS Batcher (client-side)

Chat provider'da `ds_purchase` eventleri 4 saniyelik pencere içinde birleştirilir:

```dart
// Gelen event: ds_purchase
// Önceki son item ds_purchase ise → güncelle (buyer listesine ekle)
// Değilse → yeni AnnouncementMessage ekle
// Timer her 4s'de bir "flush" eder (pencereyi kapatır)
```

---

## i18n Anahtar Listesi

ARB dosyalarına eklenmesi gereken anahtarlar:

| Anahtar | TR | EN |
|---|---|---|
| `announcementAuctionWinner` | `"🏆 {winner} açık artırmayı {price}'ye kazandı!"` | `"🏆 {winner} won the auction at {price}!"` |
| `announcementBinAccepted` | `"🛒 {buyer} hemen satın aldı — {price}"` | `"🛒 {buyer} bought it now — {price}"` |
| `announcementDsPurchase` | `"🛍 {buyer} satın aldı · Kalan: {remaining}"` | `"🛍 {buyer} purchased · Left: {remaining}"` |
| `announcementDsPurchaseBatch` | `"🛍 {buyers} ve {count} kişi daha satın aldı"` | `"🛍 {buyers} and {count} more purchased"` |

---

## Uygulama Sırası

1. **Backend** — `ws_types.py`'a `ANNOUNCEMENT` sabiti ekle
2. **Backend** — `chat_utils.py`'a `chat_announcement()` helper ekle
3. **Backend** — `auction_commands.py`: mevcut ham string çağrılarını `chat_announcement`'a geçir (refactor)
4. **Backend** — `direct_sale_commands.py`: DS tamamlandığında `chat_announcement("ds_purchase", ...)` çağır (yeni)
5. **Flutter** — `ChatItem` sealed class + `UserMessage` / `SystemAnnouncement` modelleri
6. **Flutter** — Chat list widget'ı discriminated union'a göre güncelle
7. **Flutter** — `AnnouncementTile` widget'ı yaz
8. **Flutter** — DS batcher implement et
9. **i18n** — 4 yeni anahtar × 4 dil = 16 ARB girişi ekle

---

## Notlar

- `persist: bool` parametresi: izleyici geç katıldığında tarihçeden yüklenecek duyurular
  için `True` (default); anlık sinyal niteliğindeki eventler için `False` olabilir.
- `ds_purchase` duyurusu `sale.listing_id IS NOT NULL` koşuluna bağlı değil —
  manuel DS'lerde de gösterilmeli.
- Eski `WS.MESSAGE` tabanlı duyuru mesajları (mevcut auction kodu) geçişten önce
  `WS.ANNOUNCEMENT`'a taşınmalı; aksi takdirde Flutter her iki formatı da handle etmek zorunda kalır.
