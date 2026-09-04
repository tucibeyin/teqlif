# Teqlif — Bildirim Matrisi

> Codebase analizi: `backend/app/services/notification_service.py`, `notifications.py`, `firebase_adapter.py`, `main_view_model.dart`, `messages_view_model.dart`
>
> App badge = `unread_messages + unread_notifs` (AppBadgePlus)
> `unread_notifs` = `Notification.type != "message"` filtresi uygulanmış (unread_count doğru; list endpoint BUG-2)

---

## Yüzey Tanımları

| Sütun | Kaynak |
|---|---|
| **FCM Push** | `push_notification()` → `firebase_adapter._build_message()` |
| **FCM Format** | `notification+data` → OS banner gösterir; `data-only` → uygulama kodu işler |
| **iOS fg banner** | `setForegroundNotificationPresentationOptions(alert: true)` — hepsine uygulanır |
| **Bg/killed banner** | `notification` key'i olduğunda OS otomatik gösterir |
| **App Badge** | `unreadMessages + unreadNotifs` → `AppBadgePlus.updateBadge()` |
| **Nav dot** | `mesaj dot` = `unreadMessages > 0`; `notif dot` = `unreadNotifs > 0` |
| **Gelen Kutusu** | Accepted DM thread'lerde per-conversation unread sayacı |
| **İstekler dot** | `requestCount > 0` — pending thread sayısı |
| **Bildirimler dot** | `unreadNotifs > 0` |
| **Bildirimler listesi** | `GET /api/notifications/` — şu an `type` filtresi yok (BUG-2) |
| **DB Notif** | `notifications` tablosuna kayıt yazılır mı |

---

## Sosyal

| Tür | FCM | Format | iOS fg | Bg banner | App Badge | Nav dot | Gelen | İstekler | Bildirimler dot | Bildirimler listesi | DB | Deep Link |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `follow` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/profil/@username` |
| `follow_request` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Takip İstekleri |
| `follow_accepted` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/profil/@username` |

---

## Mesajlaşma

| Tür | FCM | Format | iOS fg | Bg banner | App Badge | Nav dot | Gelen | İstekler | Bildirimler dot | Bildirimler listesi | DB | Deep Link |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `message` — accepted thread | ✓ ⚠ WS kontrolü yok | notification+data | ⚠ Her zaman (BUG-1) | ✓ | unreadMessages | mesaj dot | ✓ unread++ | — | — | ⚠ Görünür (BUG-2) | ⚠ Yazılıyor (BUG-3) | DirectChat |
| `message` — yeni istek (receiver takip etmiyor) | ✗ gönderilmez | — | — | — | — | — | — | ✓ dot artar | — | — | — | Spam koruması |
| `message` — auto-accepted (ilk kabul sonrası) | ✓ initiator'a | notification+data | ⚠ (BUG-1) | ✓ | unreadMessages | mesaj dot | ✓ | — | — | ⚠ Görünür (BUG-2) | ⚠ Yazılıyor (BUG-3) | DirectChat |

---

## Arama

| Tür | FCM | Format | iOS fg | Bg banner | App Badge | Nav dot | Gelen | İstekler | Bildirimler dot | Bildirimler listesi | DB | Deep Link |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `incoming_call` | ✓ | iOS: VoIP APNs; Android: data-only | CallKit UI | CallKit / FCM | — | — | — | — | — | — | — | CallScreen |
| `call_missed` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/profil/@username` |
| `call_accepted` | ✓ (recovery) | data-only | — | — | — | — | — | — | — | — | — | CallScreen |
| `call_ended` / `call_rejected` | ✓ (CallKit sync) | data-only | — | — | — | — | — | — | — | — | — | CallKit dismiss |

---

## İçerik & Pazar

| Tür | FCM | Format | iOS fg | Bg banner | App Badge | Nav dot | Gelen | İstekler | Bildirimler dot | Bildirimler listesi | DB | Deep Link |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `new_bid` | ✓ eşik kontrolü | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/ilan/:id` |
| `outbid` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Yayın / ilan |
| `auction_won` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/ilan/:id` |
| `auction_lost` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Bildirimler |
| `new_listing` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/ilan/:id` |
| `smart_auction_alert` / `budget_match` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/ilan/:id` / yayın |
| `stream_started` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/yayin/:id` |
| `direct_sale_purchased` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | DirectSaleDetail |
| `rating_updated` / `rating_reply` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Bildirimler |
| `price_drop_alert` / `hesitation_price` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | `/ilan/:id` |

---

## Sistem

| Tür | FCM | Format | iOS fg | Bg banner | App Badge | Nav dot | Gelen | İstekler | Bildirimler dot | Bildirimler listesi | DB | Deep Link |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `listing_removed` / `listing_deactivated` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Bildirimler |
| `listing_quality` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Bildirimler |
| `general` | ✓ | notification+data | ✓ | ✓ | unreadNotifs | notif dot | — | — | ✓ | ✓ | ✓ | Bildirimler |

---

## WS-only Eventler (FCM push yok)

`typing` · `messages_read` · `message_deleted` · `can_call_changed` · `notification` (fan-out) · `unread_count`

---

## Tespit Edilen Buglar

### BUG-1 — message FCM foreground'da da banner gösteriyor
**Kök neden:** `notification_service.py` DM push'unu `is_dm_online()` kontrolü yapmadan gönderiyor. `setForegroundNotificationPresentationOptions(alert: true)` tüm tiplere uygulandığı için iOS kullanıcı aktif sohbet ekranındayken her mesajda sistem banner'ı çıkıyor.
**Etki:** Gelen Kutusu + badge + nav dot + iOS banner → aynı mesaj 4 ayrı yerde tetikleniyor.

### BUG-2 — message tipi Bildirimler listesinde görünüyor
**Kök neden:** `GET /api/notifications/` endpoint'i `type != "message"` filtresi uygulamıyor; `unread-count` endpoint'i uyguluyor (tutarsızlık).
**Etki:** Kullanıcı okuduğu DM mesajlarını Bildirimler sekmesinde tekrar görüyor.

### BUG-3 — Her DM için gereksiz DB Notification kaydı yazılıyor
**Kök neden:** `push_notification()` her çağrıda `notifications` tablosuna kayıt yazıyor. DM'ler zaten `direct_messages` tablosunda mevcut.
**Etki:** Tablo gereksiz şişiyor; BUG-2'nin altyapısını oluşturuyor.

**3 bug'ın ortak kökü:** `message` tipi push'unun `push_notification()` üzerinden geçmesi — bu fonksiyon "kalıcı bildirim" semantiğini DM'ye uyguluyor, oysa DM geçici gerçek zamanlı bir olay.
