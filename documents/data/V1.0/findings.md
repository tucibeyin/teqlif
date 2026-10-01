# Teqlif — Tam Veri Yapısı Analizi ve Sadeleştirme Planı

**Hedef:** Kullanıcısız sistem, sıfırdan başlama. CPU/RAM/disk dostu, bakımı kolay, tip güvenli veri katmanı.  
**Kapsam:** PostgreSQL modelleri · API şemaları · Flutter modelleri · Tüm ekranlar · Genel mimari  
**Kaynak:** Canlı kod analizi — `backend/app/models/`, `backend/app/schemas/`, `backend/app/routers/`, `mobile/lib/`  
Son güncelleme: 2026-09-20

---

## İçindekiler

1. [Genel Tablo](#genel-tablo)
2. [PostgreSQL — Tüm Modeller](#postgresql--tüm-modeller)
3. [API Şemaları — Tam Envanter](#api-şemaları--tam-envanter)
4. [API Endpoint'leri — Tam Liste](#api-endpointleri--tam-liste)
5. [Flutter Modelleri — Tam Envanter](#flutter-modelleri--tam-envanter)
6. [Flutter Ekranları — Tam Liste](#flutter-ekranları--tam-liste)
7. [Tespit Edilen Sorunlar](#tespit-edilen-sorunlar)
8. [Sadeleştirme Planı — Öncelik Sırası](#sadeleştirme-planı--öncelik-sırası)

---

## Genel Tablo

| Katman | Mevcut Durum | Sorun |
|--------|-------------|-------|
| PostgreSQL | 45 tablo · `users` 47 kolon · `listings` 36 kolon | God Object tablolar |
| API Şemaları | 45+ Pydantic sınıfı · kritik endpoint'lerde `response_model` yok | Duplicate, tipsiz |
| Flutter Modelleri | 45+ sınıf · Freezed yok · tümü manuel `fromJson` | Hata riski, kod tekrarı |
| DB PK'ları | `direct_messages`, `notifications` → int4 | Sınır riski |
| DM büyümesi | Normal mesajlar hiç silinmiyor | Sonsuz büyüme |

---

## PostgreSQL — Tüm Modeller

### Kolon Özeti (45 tablo)

| Tablo | Kolon | String | Int | Bool | Float/Num | DateTime | JSON/Special | FK |
|-------|-------|--------|-----|------|-----------|----------|-------------|-----|
| **users** | **47** | 24 | 1 | 9 | 1 | 8 | 1 JSON + 1 Vector(384) + 1 Enum | 0 |
| **listings** | **36** | 11+2 Text | 1 | 1 | 6 | 6 | 1 JSONB + 1 TSVECTOR + 1 Vector(384) + 1 Enum | 1 |
| direct_messages | 18 | 6+1 Text | 2 | 5 | — | 1 | — | 3 |
| message_threads | 8 | 1 | — | 1 | — | 3 | — | 3 |
| auctions | 15 | 4 | 1 | 1 | 3 | 2 | — | 3 |
| direct_sales | 18 | 6 | 3 | 1 | 1 Numeric | 3 | — | 3 |
| direct_sale_orders | 9 | 1 | 1 | — | 1 Numeric | 1 | — | 4 |
| live_streams | 14 | 6 | 2 | 1 | — | 2 | 1 Enum | 1 |
| calls | 12 | 2 | 2 | 1 | — | 4 | — | 2 |
| call_participants | 11 | 2+1 Text | — | — | — | 4 | — | 3 |
| notifications | 8 | 2+1 Text | 1 | 1 | — | 1 | — | 1 |
| analytics_events | 11 | 7 | 1 | — | — | 1 | 1 JSONB | 1 |
| user_interactions | 7 | 2 | 2 | — | 1 | 1 | — | 1 |
| category_fields | 13 | 7 | 1 SmallInt | 2 | — | 2 | — | 0 |
| field_options | 10 | 4 | 1 SmallInt | 2 | — | 1 | — | 1 |
| stories | 8 | 4 | — | — | — | 2 | — | 1 |
| story_views | 4 | — | — | — | — | 1 | — | 2 |
| ratings | 10 | 2 | 2 | 1 | — | 3 | — | 2 |
| rating_history | 5 | 1 | 1 | — | — | 1 | — | 1 |
| ad_campaigns | 10 | 1 | 3 | — | — | 1+2 Date | — | 2 |
| gift_events | 8 | 1 | 2 | — | — | 1 | — | 3 |
| mass_notification_campaigns | 10 | — | 5 | — | — | 1 | — | 3 |
| user_interests | 7 | 2 | — | — | 1 | 1 | 1 JSONB | 1 |
| purchases | 7 | 1 | — | — | 1 | 1 | — | 3 |
| listing_offers | 5 | — | — | — | 1 | 1 | — | 2 |
| listing_impressions | 3 | — | — | — | — | 1 | — | 2 |
| follows | 5 | 1 | — | — | — | 1 | — | 2 |
| search_alerts | 7 | 2 | — | — | 1 | 1 | 1 Enum | 1 |
| referrals | 5 | 1 | — | — | — | 1 | — | 2 |
| reports | 5 | 1 | 2 | — | — | 1 | — | 2 |
| tuci_transactions | 7 | 2 | 2 | — | — | 1 | — | 1 |
| market_index | — | — | — | — | — | — | — | — |
| categories | 6 | 2 | 1 | 1 | — | — | 1 Enum | 0 |
| subcategories | 4 | 2 | 1 | 1 | — | — | — | 1 |
| favorites | 4 | — | — | — | — | 1 | — | 2 |
| user_blocks | 4 | — | — | — | — | 1 | — | 2 |
| listing_likes | 4 | — | — | — | — | 1 | — | 2 |
| story_likes | 4 | — | — | — | — | 1 | — | 2 |
| stream_likes | 4 | — | — | — | — | 1 | — | 2 |
| live_stream_viewers | 4 | — | — | — | — | 2 | — | 2 |
| states | 4 | 2 | 1 | — | — | — | — | 0 |
| districts | 3 | 1 | 1 | — | — | — | — | 1 |
| countries | 2 | 2 | — | — | — | — | — | 0 |
| app_configs | 3 | 2 | — | — | — | 1 | — | 0 |
| translations | 3 | 2+1 Text | — | — | — | — | — | 0 |

### users Tablosu — 47 Kolon Tam Listesi

```
Kimlik Doğrulama (6):
  id, email, hashed_password, status (Enum), email_verified, phone, phone_verified

Profil (5):
  username, full_name, bio, profile_image_url, profile_image_thumb_url

Premium/Plan (4):
  is_premium, plan_type, premium_since, tuci_balance

ML/Öneri (2):
  preference_embedding (Vector384), max_budget

Onboarding/Locale (3):
  onboarding_completed, locale, locale_updated_at

Admin (2):
  is_admin, is_shadowbanned

Sosyal Medya Linkleri (7): ← tümü NULL olan alan grubu
  website_url, instagram_url, kick_url, twitch_url,
  facebook_url, youtube_url, tiktok_url

Bildirim Tercihleri (1): ← JSON — tip güvensiz
  notification_prefs (JSON)

GDPR Onayları (6):
  age_confirmed_at, cross_border_consent_given, cross_border_consent_at,
  cross_border_consent_version, cross_border_consent_revoked_at,
  cross_border_consent_ip, cross_border_consent_locale

Referral (3):
  referral_code, referral_code_expires_at, pending_referred_by

Timestamps (1):
  created_at
```

### Mevcut İndeksler

**direct_messages:**
- `ix_direct_messages_conv_created (sender_id, receiver_id, created_at)` — OR sorgusu için yetersiz
- `ix_dm_receiver_is_read (receiver_id, is_read)`
- `ix_dm_content_type_created (content_type, created_at)` — cleanup için

**message_threads:**
- PK: `(user_a_id, user_b_id)` — canonical pair (user_a_id < user_b_id)
- `ix_message_threads_user_b (user_b_id)`

**notifications:**
- `ix_notifications_user_created (user_id, created_at)`
- `ix_notifications_user_is_read (user_id, is_read)`

**listings:**
- TSVECTOR ve Vector(384) — FTS ve vektör arama için

### FK İlişki Haritası

```
users (merkez)
  ← listings.user_id
  ← auctions.winner_id
  ← direct_sales.host_id
  ← direct_sale_orders.seller_id / buyer_id
  ← direct_messages.sender_id / receiver_id
  ← message_threads.user_a_id / user_b_id / initiator_id
  ← calls.caller_id / callee_id
  ← call_participants.user_id / invited_by
  ← notifications.user_id
  ← follows.follower_id / followed_id
  ← gift_events.sender_id / receiver_id
  ← ad_campaigns.seller_id
  ← stories.user_id
  ← user_interests.user_id
  ← referrals.*
  ← tuci_transactions.user_id
  ← user_blocks.blocker_id / blocked_id
  ← ratings.rater_id / rated_user_id
  ← listing_impressions.user_id
  ← favorites.user_id
  ← listing_likes.user_id / story_likes.user_id / stream_likes.user_id

listings (ikincil merkez)
  ← auctions.listing_id
  ← direct_sales.listing_id
  ← direct_sale_orders.listing_id
  ← direct_messages.listing_id
  ← ad_campaigns.listing_id
  ← listing_offers.listing_id
  ← listing_impressions.listing_id
  ← favorites.listing_id
  ← listing_likes.listing_id
  ← purchases.listing_id

live_streams
  ← auctions.stream_id
  ← direct_sales.stream_id
  ← gift_events.stream_id
  ← live_stream_viewers.stream_id
  ← stream_likes.stream_id
  ← mass_notification_campaigns.stream_id

category_fields
  ← field_options.field_id

calls
  ← call_participants.call_id

auctions
  ← purchases.auction_id
```

### Cleanup Görevleri (worker.py)

| Tablo | Kural | Periyot |
|-------|-------|---------|
| notifications | created_at < 30 gün | Haftalık |
| analytics_events | created_at < 90 gün | Pazartesi 04:00 |
| user_interactions | created_at < 90 gün | Salı 04:00 |
| stream_likes | created_at < 7 gün | Haftalık |
| direct_messages | is_hidden=TRUE AND created_at < 60 gün | Haftalık |
| direct_messages (medya) | content_type IN (...) AND created_at < ... | Haftalık |
| listing_impressions | seen_at < 30 gün | Günlük 05:00 |
| stories | expires_at geçmiş | Periyodik |
| listings (pasif) | expire + inactive | Periyodik |
| **direct_messages (normal)** | **HİÇ SİLİNMİYOR** | **— ← KRİTİK HATA** |

---

## API Şemaları — Tam Envanter

### `schemas/user.py`

**UserRegister** (10 alan)
- Zorunlu: `email`, `username`, `full_name`, `password`
- Opsiyonel: `phone`, `referred_by`, `lang`="tr", `age_confirmed`=False, `cross_border_consent`=False, `consent_locale`

**UserLogin** (2 zorunlu)
- `login_identifier`, `password` — model_validator ile eski username/email field'larını da kabul eder

**UserOut** (26 alan — en büyük response şeması)
- 7 zorunlu: `id`, `email`, `username`, `full_name`, `status`, `is_verified`, `created_at`
- 4 defaultlu: `is_private`=False, `phone_verified`=False, `is_premium`=False, `onboarding_completed`=False
- 15 optional: `locale`, `locale_updated_at`, `phone`, `profile_image_url`, `profile_image_thumb_url`, `plan_type`, `bio`, `website_url`, `instagram_url`, `kick_url`, `twitch_url`, `facebook_url`, `youtube_url`, `tiktok_url`, `fcm_token`

**UserUpdate** (15 alan, tümü Optional)
- `full_name`, `username`, `locale`, `locale_updated_at`, `profile_image_url`, `profile_image_thumb_url`, `bio`, `website_url`, `instagram_url`, `kick_url`, `twitch_url`, `facebook_url`, `youtube_url`, `tiktok_url`, `is_private`

**TokenOut** (4 alan + nested)
- `access_token`, `refresh_token`, `token_type`="bearer", `user: UserOut` (26 alan nested)

**NotificationPrefs** (14 alan, tümü defaultlu)
- 9 bool: `messages`, `follows`, `auction_won`, `stream_started`, `new_listing`, `new_bid`, `outbid`, `smart_alert`, `ratings`, `receive_blast_notifications`
- `bid_threshold_tl`=0, `quiet_hours_enabled`=False, `quiet_from`="22:00", `quiet_to`="08:00"

**ConsentOut** (6 alan): `given`, `at`?, `version`?, `revoked_at`?, `ip`?, `locale`?

**Diğer:** VerifyEmail, ResendCode, ChangePasswordConfirm, ForgotPassword, ResetPassword, ConsentUpdate

---

### `schemas/listing.py`

**ListingOfferCreate** (1 alan): `amount` (float)

**ListingOfferResponse** (7 alan): `id`, `listing_id`, `amount`, `created_at`, `user_id`, `username`, `profile_image_url`?

---

### `schemas/auction.py`

**AuctionStart** (4 alan): `start_price` (zorunlu), `item_name`?, `buy_it_now_price`?, `listing_id`?
- Validator: listing_id veya item_name'den biri zorunlu

**BidIn** (1 alan): `amount` (float)

**BidOut** (3 alan): `bidder_username`, `amount`, `created_at`

**AuctionStateOut** (10 alan — 9 endpoint'te kullanılıyor)
- Zorunlu: `status`, `bid_count`=0, `winner_accepted`=False
- Opsiyonel: `item_name`, `start_price`, `buy_it_now_price`, `current_bid`, `current_bidder`, `listing_id`, `bin_buyer_username`

---

### `schemas/message.py`

**MessageOut** (13 alan)
- 8 zorunlu: `id`, `sender_id`, `receiver_id`, `sender_username`, `content`, `content_type`="text", `is_read`, `created_at`
- 5 opsiyonel: `media_url`, `thumbnail_url`, `duration_secs`, `file_name`, `file_size`

**ConversationOut** (8 alan)
- 6 zorunlu: `user_id`, `username`, `full_name`, `last_message`, `last_at`, `unread_count`
- 2 defaultlu: `last_message_type`="text", `is_request`=False ← flag anti-pattern

**SendMessageIn** (3 alan): `receiver_id`, `content` (1-1000 char), `listing_id`?

---

### `schemas/notification.py`

**NotificationOut** (8 alan): `id`, `user_id`, `type`, `title`, `is_read`, `created_at`, `body`?, `related_id`?

**UnreadCountOut** (1 alan): `count`

---

### `schemas/analytics.py`

**AnalyticsEventCreate** (7 alan): `session_id`, `event_type` (zorunlu) + `url`, `device_type`, `os`, `browser`, `event_metadata`? (Dict)

**FeedEventCreate** (8 alan, tümü defaultlu)
- `listing_id`, `event_type` (Literal skip/impression/click), `dwell_time_ms`, `content_type`, `slot_index`, `stream_category`, `listing_condition`, `listing_subcategory`

**FeedEventBatch** (1 alan): `events: List[FeedEventCreate]` (max 500)

**SearchEventCreate** (4 alan): `query` (zorunlu), `category`, `result_count`, `subcategory`

---

### `schemas/block.py`

**BlockedUserOut** (4 alan): `id`, `username`, `full_name`, `profile_image_url`?
**BlockStatusOut** (1 alan): `is_blocked`

---

### `schemas/call.py`

**CallParticipantOut** (5 alan): `user_id`, `username`, `avatar`?, `role`, `status`

**AcceptGroupInviteResponse** (4 alan + nested list)
- `livekit_token`, `livekit_url`, `room_name`, `participants: List[CallParticipantOut]`

**CallOut** (11 alan): `id`, `caller_id`, `callee_id`, `room_name`, `status`, `had_video`, `max_participants`, `started_at`, `accepted_at`?, `ended_at`?, `duration_seconds`?

---

### `schemas/direct_sale.py`

**DirectSaleStartIn** (5 alan): `price`, `stock_quantity` (zorunlu) + `listing_id`?, `title`?, `proof_image_url`?

**DirectSaleStateOut** (10 alan)
- 6 zorunlu: `status`, `sale_id`, `title`, `price`, `total_stock`, `remaining_stock`
- 4 opsiyonel: `product_image_url`, `proof_image_url`, `end_reason`, `listing_id`

**DirectSaleSummaryOut** (16 alan — union type problemi)
- Her zaman dolu: `role`, `sale_id`, `item_name`, `status`
- Her zaman opsiyonel: `proof_image_url`, `image_url`, `end_reason`, `ended_at`
- Sadece role=="seller": `total_revenue`, `total_quantity_sold`, `order_count`, `seller_username`
- Sadece role=="buyer": `buyer_quantity`, `buyer_unit_price`, `buyer_total`, `buyer_order_status`

**DirectSaleOrderOut** (7 alan): `id`, `buyer_username`, `quantity`, `unit_price`, `total_price`, `status`, `created_at`

**DirectSaleSuggestionsOut** (6 alan, 4 opsiyonel)

---

### `schemas/field_config.py`

**FieldOptionSchema** (5 alan): `value`, `label`, `parent_option_value`?, `exclusion_group`?, `is_exclusive`=False

**ExtraFieldSchema** (8 alan + nested): `key`, `label_key`, `type`, `required`, `position`, `unit`?, `depends_on`?, `options: List[FieldOptionSchema]`

**FieldConfigResponse** (2 alan — 3 seviye nested): `subcategory`, `fields: List[ExtraFieldSchema]` → içinde `options: List[FieldOptionSchema]`

---

### `schemas/story.py`

**StoryAuthorOut** (5 alan): `id`, `username`, `full_name`, `profile_image_url`?, `profile_image_thumb_url`?

**StoryItemOut** (9 alan): `id`, `story_type`, `likes_count`=0, `is_liked`=False + `video_url`?, `thumbnail_url`?, `expires_at`?, `created_at`?, `stream_id`?

**UserStoryGroupResponse** (3 alan — 2 seviye nested): `user: StoryAuthorOut`, `items: List[StoryItemOut]`, `latest_activity_at`

**StoryViewersResponse** (3 alan): `story_id`, `viewers: List[StoryViewerOut]`, `total`

---

### `schemas/stream.py`

**StreamHostOut** (3 alan): `id`, `username`, `full_name`

**StreamOut** (10 alan + nested): `id`, `room_name`, `title`, `category`, `viewer_count`, `started_at`, `likes_count`=0, `subcategory`?, `thumbnail_url`?, `host: StreamHostOut`

**StreamTokenOut** (5 alan): `stream_id`, `room_name`, `livekit_url`, `token`, `category`

**JoinTokenOut** (8 alan): `stream_id`, `room_name`, `livekit_url`, `token`, `title`, `category`, `host_username`, `host_livekit_identity`

**SwipeLiveConfig** (3 alan — 3 seviye nested): `streams: List[StreamOut]`, `listings_per_group`, `preferred_listing_categories: List[str]`

---

## API Endpoint'leri — Tam Liste

### Auth (`/auth`)
```
POST   /auth/login                      → TokenOut
POST   /auth/register                   → TokenOut
POST   /auth/verify                     → TokenOut
POST   /auth/resend-code
POST   /auth/refresh                    → TokenOut
DELETE /auth/delete-account
GET    /auth/me                         → UserOut (response_model EKSİK)
PATCH  /auth/me
POST   /auth/forgot-password
POST   /auth/reset-password
POST   /auth/change-password
GET    /auth/init                       → (response_model EKSİK)
POST   /auth/device-tokens
POST   /onboarding/interests
GET    /auth/me/commerce/purchases      → (response_model EKSİK)
GET    /auth/me/commerce/sales          → (response_model EKSİK)
GET    /auth/consent
POST   /auth/consent
GET    /auth/notification-prefs         → NotificationPrefs
PATCH  /auth/notification-prefs
```

### Listings (`/listings`)
```
GET    /listings                        → (response_model EKSİK — en sık çağrılan)
GET    /listings/{id}                   → (response_model EKSİK)
POST   /listings
PUT    /listings/{id}
DELETE /listings/{id}
POST   /listings/{id}/like
POST   /listings/{id}/toggle
GET    /listings/{id}/price-signal      → ListingPriceSignalOut
GET    /listings/{id}/reactivation-cost
GET    /listings/{id}/offers
POST   /listings/{id}/offers
GET    /listings/{id}/audience-estimate
GET    /listings/{id}/notification-cooldown
POST   /listings/{id}/send-mass-notification
```

### Streams (`/streams`)
```
GET    /streams/active                  → List[StreamOut]
GET    /streams/recommended             → List[StreamOut]
GET    /streams/following/live          → List[StreamOut]
GET    /streams/suggested-streamers
GET    /streams/swipe-live-config       → SwipeLiveConfig
GET    /streams/history
POST   /streams/start                   → StreamTokenOut
GET    /streams/{id}                    → StreamOut
DELETE /streams/{id}
POST   /streams/{id}/like
POST   /streams/{id}/thumbnail
GET    /streams/{id}/token              → StreamTokenOut
GET    /streams/{id}/join-token         → JoinTokenOut
POST   /streams/{id}/confirm-live
GET    /streams/{id}/viewers
POST   /streams/{id}/pip-enter
POST   /streams/{id}/pip-exit
POST   /streams/{id}/cohost/invite
POST   /streams/{id}/cohost/accept      → StreamTokenOut
POST   /streams/{id}/cohost/leave
DELETE /streams/{id}/cohost/remove
GET    /streams/{id}/audience-insights
GET    /streams/{id}/commerce-activity
POST   /analytics/swipe-live-events
```

### Auction (`/auction`)
```
GET    /auction/{streamId}              → AuctionStateOut
POST   /auction/{streamId}/start        → AuctionStateOut
POST   /auction/{streamId}/pause        → AuctionStateOut
POST   /auction/{streamId}/resume       → AuctionStateOut
POST   /auction/{streamId}/end          → AuctionStateOut
POST   /auction/{streamId}/bid          → AuctionStateOut
POST   /auction/{streamId}/accept       → AuctionStateOut
POST   /auction/{streamId}/buy-it-now   → AuctionStateOut
POST   /auction/{streamId}/buy-it-now/accept → AuctionStateOut
POST   /auction/{streamId}/buy-it-now/reject → AuctionStateOut
GET    /auction/{streamId}/bids         → List[BidOut]
```

### Direct Sale (`/direct-sales`)
```
POST   /direct-sales/{streamId}/start       → DirectSaleStateOut
PATCH  /direct-sales/{saleId}/pause         → DirectSaleStateOut
PATCH  /direct-sales/{saleId}/resume        → DirectSaleStateOut
PATCH  /direct-sales/{saleId}/end           → DirectSaleStateOut
PATCH  /direct-sales/{saleId}/cancel
POST   /direct-sales/{saleId}/purchase      → DirectSaleStateOut
GET    /direct-sales/{saleId}/summary       → DirectSaleSummaryOut
GET    /direct-sales/{streamId}/state       → DirectSaleStateOut
GET    /direct-sales/{saleId}/orders        → List[DirectSaleOrderOut]
```

### Messages (`/messages`)
```
GET    /messages/conversations          → List[ConversationOut]
GET    /messages/requests               → List[ConversationOut]  ← aynı şema, farklı veri
GET    /messages/conversation/{userId}  → List[MessageOut]
GET    /messages/{id}                   → MessageOut
POST   /messages/send                   → MessageOut
GET    /messages/unread-count           → UnreadCountOut
GET    /messages/requests/count
POST   /messages/requests/{id}/accept
DELETE /messages/requests/{id}
```

### Notifications (`/notifications`)
```
GET    /notifications/                  → List[NotificationOut]
POST   /notifications/mark-all-read
GET    /notifications/unread-count      → UnreadCountOut
GET    /notifications/settings
PATCH  /notifications/settings
```

### Calls (`/calls`)
```
POST   /calls/start
GET    /calls/active
POST   /calls/{id}/accept
POST   /calls/{id}/reject
POST   /calls/{id}/end
POST   /calls/{id}/missed
POST   /calls/{id}/connected
GET    /calls/{id}/status
GET    /calls/{id}/callee-token
GET    /calls/history                   → List[CallOut]
POST   /calls/{id}/invite
POST   /calls/{id}/participants/{pId}/accept
POST   /calls/{id}/participants/{pId}/reject
POST   /calls/{id}/participants/{pId}/leave
POST   /calls/{id}/participants/{userId}/remove
```

### Stories (`/stories`)
```
GET    /stories/following               → List[UserStoryGroupResponse]
GET    /stories/mine                    → MyStoriesResponse
POST   /stories/upload
POST   /stories/{id}/view
POST   /stories/{id}/like
GET    /stories/{id}/viewers            → StoryViewersResponse
DELETE /stories/{id}
```

### Analytics (`/analytics`)
```
GET    /analytics/pro-insights
GET    /analytics/pro/metrics
GET    /analytics/market-trends
GET    /analytics/demand-radar
GET    /analytics/demand-trends
GET    /analytics/seller-report/{streamId}
GET    /analytics/competitor-radar/{listingId}
GET    /analytics/category-velocity
GET    /analytics/video-roi
GET    /analytics/gallery-stats
GET    /analytics/video-performance
GET    /analytics/my-feed-stats
GET    /analytics/ai-price-credits
GET    /analytics/reactivation-credits
POST   /analytics/price-estimate
POST   /analytics/interaction
POST   /analytics/track-search
POST   /analytics/track
```

### Ads / Leads
```
GET    /ads/boost-credits
GET    /ads/campaigns/{id}/report
POST   /ads/click/{id}
POST   /ads/impression/{id}
GET    /leads/audience-size
GET    /leads/blast-credits
GET    /leads/retargeting-audience/{id}
POST   /leads/send-blast
POST   /leads/send-retargeting
GET    /leads/mass-notification-report
```

### Users / Config / Misc
```
GET    /users/{username}
PATCH  /users/{id}/call-permission
GET    /users/blocked                   → List[BlockedUserOut]
POST   /users/{id}/block
DELETE /users/{id}/block
GET    /users/{id}/block-status         → BlockStatusOut
GET    /config/version
GET    /categories
GET    /categories/{key}/fields         → FieldConfigResponse
POST   /upload
POST   /upload/listing-video
GET    /wallet/balance
POST   /wallet/send-gift
GET    /wallet/transaction/{id}
GET    /follows/{userId}
GET    /following
POST   /follows/{userId}
DELETE /follows/{userId}
GET    /follows/requests
POST   /follows/requests/{id}/accept
DELETE /follows/requests/{id}
```

---

## Flutter Modelleri — Tam Envanter

**Toplam:** 16 dosya, 45+ sınıf, Freezed YOK, tümü manuel `fromJson`

### `models/user.dart` — `User`
```dart
id (int), email (String), username (String), fullName (String),
isVerified (bool), locale (String?), localeUpdatedAt (String?),
isPrivate (bool), phone (String?), phoneVerified (bool),
profileImageUrl (String?), profileImageThumbUrl (String?),
isPremium (bool), planType (String?), onboardingCompleted (bool)
```
Kullanıldığı yer: `auth_service.dart` — profil ekranları `StorageService` üzerinden dolaylı erişiyor.

### `models/stream.dart` — 5 sınıf
```dart
StreamHost: id, username
StreamOut: id, roomName, title, category, subcategory?, viewerCount, host (StreamHost), thumbnailUrl?
StreamTokenOut: streamId, roomName, livekitUrl, token, category
JoinTokenOut: streamId, roomName, livekitUrl, token, title, category, hostUsername, hostLivekitIdentity
SwipeLiveConfig: streams (List<StreamOut>), listingsPerGroup, preferredListingCategories (List<String>)
```
Kullanıldığı ekranlar: `live_list_screen`, `swipe_live_screen`, `host_stream_screen`, `search_screen` + 9 dosya

### `models/listing_filter_state.dart` — `ListingFilterState`
```dart
category?, subcategory?, city?, condition?, sortBy?,
minPrice?, maxPrice?, searchQuery?, dateFrom?, dateTo?,
extraFields (Map<String, dynamic>)  ← kasıtlı dinamik (katalog alanları)
```
En fazla kullanılan model — 15 dosyada.

### `models/direct_sale.dart` — 6 sınıf
```dart
DirectSaleState: status, saleId, title, price, totalStock, remainingStock,
                 productImageUrl?, proofImageUrl?, endReason?, listingId?,
                 lastPurchaseBuyer?, lastPurchaseQty?
DirectSaleOrder: id, buyerUsername, quantity, unitPrice, totalPrice, status, createdAt
DirectSaleSummary: role, saleId, itemName, proofImageUrl?, imageUrl?, status,
                   endReason?, endedAt?, totalRevenue?, totalQuantitySold?,
                   orderCount?, sellerUsername?, buyerQuantity?, buyerUnitPrice?,
                   buyerTotal?, buyerOrderStatus?
CommercePurchase: type (CommerceType), id, saleId?, itemName, finalPrice, unitPrice?, quantity?
CommerceSale: (satıcı tarafı — benzer alanlar)
ListingPriceSignal: (fiyat sinyali)
```

### `models/auction.dart` — `AuctionState`
```dart
status, itemName?, startPrice?, buyItNowPrice?, currentBid?, currentBidder?,
bidCount (int), listingId?, isBoughtItNow (bool), buyerUsername?,
pendingBuyerUsername?, errorMessage?, winnerAccepted (bool)
```

### `models/story.dart` — 4 sınıf
```dart
StoryAuthor: id, username, fullName, profileImageUrl?, profileImageThumbUrl?
StoryItem: id, storyType, videoUrl?, thumbnailUrl?, expiresAt?, createdAt?,
           streamId?, likesCount, isLiked
StoryViewer: userId, username, fullName, profileImageThumbUrl?, viewedAt
UserStoryGroup: user (StoryAuthor), items (List<StoryItem>), latestActivityAt
```

### `models/pro_insights_data.dart` — 11 sınıf (1 ekranda kullanılıyor)
```dart
ProKpis: revenue30d, revenueGrowthPct?, sales30d, bids30d, activeListings, totalRevenue
ProFunnel: views, dwells, hesitations, bids, sales, viewToBidPct, bidToSalePct
HotLead: listingId, title, price?, category, subcategory?, views30d, hesitations30d,
         heatScore, isBoosted
PriceIntel: listingId, title, yourPrice, marketAvg, diffPct, signal, category?, subcategory?
BestStream: (en iyi yayın verisi)
StreamStats: totalStreams, streams30d, avgViewers, peakViewers, avgDurationMin,
             bestStreams (List<BestStream>)
PeakHour: (saat bazlı yoğunluk)
ProTip: (ipuçları)
SearchVisibility: (arama görünürlüğü)
ProMetrics: (metrikler)
ProInsightsData: kpis (ProKpis), funnel (ProFunnel), hotLeads (List<HotLead>),
                 priceIntel (List<PriceIntel>), streamStats (StreamStats),
                 peakHours (List<PeakHour>), tips (List<ProTip>)
```

### `models/catalog.dart` — 4 sınıf (4 katman nested)
```dart
CatalogOption: value, label, labelKey, parentOptionValue?, exclusionGroup?, isExclusive
CatalogField: key, labelKey, type, required, unit?, dependsOn?, options (List<CatalogOption>)
CatalogSubcategory: key, fields (List<CatalogField>)
CatalogCategory: key, subcategories (List<CatalogSubcategory>), isListable
```

### `models/call_participant.dart` — 2 sınıf
```dart
CallParticipant: userId, username, avatar?, role, status
GroupInvite: callId, roomName, livekitToken, livekitUrl, inviterId,
             inviterUsername, inviterAvatar?, participantId
```

### `models/call_history_item.dart` — `CallHistoryItem`
```dart
callId, status, role, durationSeconds?, startedAt?,
otherUserId?, otherUsername?, otherAvatar?
```

### `models/call_event.dart` — 10 sealed sınıf
```dart
CallSignal (sealed base)
IncomingCallSignal: callId, callerId, callerUsername, callerAvatar?, locale?
CallAcceptedSignal, CallRejectedSignal, CallEndedSignal, CallMissedSignal
WsConnectedSignal
IncomingCallTapSignal: data (Map<String, dynamic>)     ← tiplanmamış
IncomingCallAutoAcceptSignal: data (Map<String, dynamic>) ← tiplanmamış
UnknownCallSignal
```

### `models/chat.dart` — `ChatMessage`
```dart
id, username, profileImageUrl?, content, createdAt,
isSystem, isMod, isHost, isAuctionResult,
announcementType?, announcementPayload? (Map<String, dynamic>)  ← tiplanmamış
```
Kullanıldığı yer: sadece `chat_panel` widget'ı.

### `models/commerce_activity.dart` — 3 sealed sınıf
```dart
CommerceEvent (sealed)
AuctionBidEvent: actor, amount, createdAt
DsPurchaseEvent: actor, unitPrice, quantity, createdAt
CommerceEventGroup: title?, groupType, events (List<CommerceEvent>)
```
fromJson yok — WS eventi olarak elle oluşturuluyor.

### `models/listing_offer.dart` — `ListingOffer`
```dart
id, listingId, userId, username, profileImageUrl?, amount, createdAt
```

### `models/mass_notif_eligibility.dart` — 3 sealed sınıf
```dart
MassNotifEligibility (sealed)
MassNotifAvailable
MassNotifCooldownActive: secondsRemaining (int)
MassNotifUnavailable: reason (MassNotifUnavailableReason)
```

### `models/enums.dart`
```dart
ListingStatus, UserStatus, CategoryStatus, SearchAlertStatus
```

---

## Flutter Ekranları — Tam Liste

**Toplam:** 49 ekran, 259 Dart dosyası, Riverpod state management, MVVM mimari

### Auth Ekranları (`lib/screens/auth/`)
| Ekran | API Çağrıları |
|-------|--------------|
| `login_screen.dart` | POST /auth/login, POST /auth/refresh |
| `register_screen.dart` | POST /auth/register |
| `verify_screen.dart` | POST /auth/verify, POST /auth/resend-code |
| `forgot_password_screen.dart` | POST /auth/forgot-password |
| `reset_password_screen.dart` | POST /auth/reset-password |
| `category_onboarding_screen.dart` | POST /onboarding/interests, GET /categories |

### Ana / Kapsayıcı Ekranlar
| Ekran | API Çağrıları |
|-------|--------------|
| `splash_screen.dart` | GET /auth/me, GET /config/version |
| `main_screen.dart` | WS bağlantısı, notifications, deep links |
| `home_screen.dart` | GET /feed/recent, /feed/hesitated, /feed/for-you |
| `search_screen.dart` | GET /feed/for-you, /feed/recent, /streams/suggested-streamers |

### Profil ve Hesap Ekranları
| Ekran | API Çağrıları |
|-------|--------------|
| `profile_screen.dart` | GET /users/{username}, wallet balance stream |
| `public_profile_screen.dart` | GET /users/{username}, follow/unfollow, block |
| `account_info_screen.dart` | GET /auth/me, email/phone değişim |
| `notification_settings_screen.dart` | GET/PATCH /notifications/settings |
| `blocked_users_screen.dart` | GET/DELETE /users/blocked |
| `follow_list_screen.dart` | GET /follows/{userId}, follow toggle |
| `follow_requests_screen.dart` | GET /follows/requests |
| `my_ratings_screen.dart` | GET /ratings/me/received, GET /ratings/me/given |

### İlan Ekranları
| Ekran | API Çağrıları |
|-------|--------------|
| `listing_detail_screen.dart` | GET /listings/{id}, GET /listings/{id}/audience-estimate |
| `create_listing_screen.dart` | POST /listings, katalog alanlar |
| `edit_listing_screen.dart` | PUT /listings/{id} |
| `listing_analytics_screen.dart` | GET /analytics/video-roi, /gallery-stats, /video-performance |
| `direct_sale_detail_screen.dart` | GET /direct-sales/{id}/summary |

### Satın Alma / Satış Ekranları
| Ekran | API Çağrıları |
|-------|--------------|
| `purchases_screen.dart` | GET /auth/me/commerce/purchases |
| `purchase_detail_screen.dart` | GET /listings/{id}, GET /categories |
| `sales_screen.dart` | GET /auth/me/commerce/sales |
| `sale_detail_screen.dart` | GET /listings/{id}, GET /categories |

### Canlı Yayın Ekranları (`lib/screens/live/`)
| Ekran | API Çağrıları | Modeller |
|-------|--------------|---------|
| `host_stream_screen.dart` | GET /streams/{id}, WS auctions/direct-sales | StreamOut, AuctionState, DirectSaleState |
| `live_list_screen.dart` | GET /streams/active, /recommended, /suggested-streamers, WS | StreamOut |
| `swipe_live_screen.dart` | GET /streams/swipe-live-config, swipe events | StreamOut, SwipeLiveConfig |
| `seller_report_screen.dart` | GET /analytics/seller-report/{streamId} | — |

### Analytics / Pro Ekranları
| Ekran | API Çağrıları |
|-------|--------------|
| `pro_insights_screen.dart` | GET /analytics/pro-insights, /analytics/pro/metrics |
| `pro_hub_screen.dart` | GET /auth/me, blast/boost/ai-desc/reactivation credits |
| `pro_stream_analytics_screen.dart` | GET /analytics/streams/{id} |
| `live_stream_analytics_screen.dart` | GET /analytics/streams/{id} (viewer side) |
| `live_stream_history_screen.dart` | GET /streams/history |
| `market_intelligence_screen.dart` | GET /analytics/market-trends, /analytics/demand-radar |
| `demand_trends_screen.dart` | GET /analytics/demand-trends |
| `competitor_radar_screen.dart` | GET /analytics/competitor-radar/{id}, /analytics/category-velocity |
| `retargeting_screen.dart` | GET /leads/retargeting-audience/{id}, POST /leads/send-retargeting |
| `ad_report_screen.dart` | GET /ads/campaigns/{id}/report |

### Çağrı Ekranları
| Ekran | API Çağrıları | Modeller |
|-------|--------------|---------|
| `call_screen.dart` | POST /calls/{id}/accept, /calls/{id}/end | CallParticipant |
| `incoming_call_screen.dart` | POST /calls/{id}/accept, /calls/{id}/reject | — |
| `call_history_screen.dart` | GET /calls/history | CallHistoryItem |

### Mesajlaşma / Story / Diğer
| Ekran | API Çağrıları |
|-------|--------------|
| `messages_screen.dart` | GET /messages/conversations, /notifications/unread-count, WS |
| `story_viewer_screen.dart` | GET /stories/following, /stories/mine, POST /stories/{id}/view |
| `force_update_screen.dart` | GET /config/version |
| `faq_screen.dart` | Statik / lokalizasyon |

---

## Tespit Edilen Sorunlar

### Sorun S1 [KRİTİK] — `direct_messages`: int4 PK + Normal Mesajlar Silinmiyor

`message.py:16` — `id: Mapped[int]` = int4, max 2,147,483,647  
`worker.py:408` — cleanup: yalnızca `is_hidden=TRUE AND created_at < 60 gün`  
Normal mesajlar hiç silinmiyor → tablo sonsuz büyür.

Büyüme: 100K kullanıcı × 5 msg/gün = 500K/gün → int4 dolma ~11.7 yıl.  
`ALTER COLUMN TYPE BIGINT` = tam tablo kilidi: 15MB'da 1 sn, 500M satırda saatler.

### Sorun S2 [KRİTİK] — `direct_messages`: OR Sorgusu

`get_messages_query.py:63` — çift Index Scan → BitmapOr → Heap Fetch.  
`message_threads` canonical pair (`user_a_id < user_b_id`) tutuyor.  
`direct_messages`'ta `thread_id` yok → OR kaçınılmaz.

### Sorun S3 [KRİTİK] — `users` Tablosu: 47 Kolon God Object

6 farklı sorumluluk tek tabloda. 7 sosyal medya URL çoğunlukla NULL.  
`notification_prefs` JSONB — tip güvensiz, kısmi güncelleme için tüm JSON yeniden yazılıyor.

### Sorun S4 [KRİTİK] — Kritik Endpoint'lerde `response_model` Yok

`GET /listings`, `GET /listings/{id}`, `GET /auth/me`, `GET /auth/init`,  
`GET /auth/me/commerce/purchases`, `GET /auth/me/commerce/sales` —  
Pydantic doğrulama çalışmıyor. Internal field'lar client'a sızabilir.

### Sorun S5 [ÖNEMLİ] — 4 Duplicate Partial-User Şeması

Aynı `users` tablosundan 4 ayrı şema:
- `UserOut` (26 alan), `StoryAuthorOut` (5), `BlockedUserOut` (4), `StreamHostOut` (3)

Ortak `UserMiniOut` base yok.

### Sorun S6 [ÖNEMLİ] — `DirectSaleSummaryOut`: Flat Union Type

16 alanda 2 birbirini dışlayan alan grubu (seller / buyer).  
Discriminated union olmalı.

### Sorun S7 [ÖNEMLİ] — Flutter: Freezed Yok

45+ sınıf, tümü manuel `fromJson`. API alan adı veya tip değişikliği → runtime crash.  
`copyWith` bazı modellerde hiç yok.

### Sorun S8 [ÖNEMLİ] — Tiplanmamış Dinamik Alanlar (Flutter)

`ChatMessage.announcementPayload: Map<String, dynamic>?` — tip yok  
`IncomingCallTapSignal.data: Map<String, dynamic>` — ham veri  
(`ListingFilterState.extraFields` kasıtlı — katalog dinamik, kabul edilebilir)

### Sorun S9 [ORTA] — `notifications` int4 PK

30 günde siliniyor → bounded risk. Ama sıfırdan başlarken değiştirmek maliyetsiz.

### Sorun S10 [ORTA] — `ConversationOut` `is_request` Flag Anti-Pattern

`/conversations` ve `/requests` aynı şema, `is_request: bool` ile ayrılıyor.  
İki ayrı şema daha temiz.

### Sorun S11 [ORTA] — `AuctionStateOut` Aşırı Kullanım

9 endpoint, 1 şema. Her durumda farklı alanlar dolu.  
İleride discriminated union daha temiz olur.

### Sorun S12 [ORTA] — `StoryItemOut` İki Tip, Tek Şema

`story_type='video'` → video alanları dolu. `story_type='live_redirect'` → `stream_id` dolu.  
Discriminated union daha açık.

### Sorun S13 [ORTA] — `UserOut` 26 Alan, 7 Sosyal URL

Her response'da 7 boş sosyal URL taşınıyor.  
`UserOut` (core) + `UserProfileOut` (sosyal linkler dahil) ayrılabilir.

### Sorun S14 [ORTA] — `ProInsightsData`: 11 Sınıf, 1 Ekran

Sadece `pro_insights_screen.dart`'ta kullanılıyor.  
Backend'deki yoğunluk da gerçek — bu analitik veri doğası gereği kompleks.

### Sorun S15 [DÜŞÜK] — `StreamTokenOut` vs `JoinTokenOut` Örtüşmesi

Her ikisi de LiveKit bağlantı bilgisi. Ortak base ile birleştirilebilir.

### Sorun S16 [BİLGİ] — `analytics_events` + `user_interactions` Çift Yazma Kasıtlı

ClickHouse raw → PG 22 dakika gecikme ile kopyalanıyor.  
Öneri motoru PG JOINs gerektiriyor. Değiştirilmemeli.

---

## Sadeleştirme Planı — Öncelik Sırası

### Hemen Yapılacaklar (DB sıfırdan, maliyetsiz)

| # | Sorun | Eylem | Dosya |
|---|-------|-------|-------|
| 1 | S1 | `direct_messages` + `notifications` → BigInteger PK | `models/message.py`, `models/notification.py` |
| 2 | S1 | DM retention policy: her iki taraf da silmişse 365 gün sonra sil | `worker.py` |
| 3 | S2 | `message_threads`'e `id BIGINT` sequential PK ekle | `models/message_thread.py` |
| 4 | S2 | `direct_messages`'a `thread_id BIGINT FK` + `(thread_id, id DESC)` index | `models/message.py` |
| 5 | S2 | OR sorgusunu `thread_id =` equality ile değiştir | `use_cases/messages/queries/` |
| 6 | S3 | `users` tablosunu böl: `user_social_links`, `user_consents`, referral bölümünü kaldır | `models/user.py` + 2 yeni model |
| 7 | S3 | `notification_prefs` JSON → `user_notification_prefs` ayrı tablo | `models/user_notification_prefs.py` |
| 8 | S4 | Tüm kritik endpoint'lere `response_model=` ekle | `routers/listings.py`, `routers/auth.py` |
| 9 | S5 | `UserMiniOut` base şema oluştur, StoryAuthorOut / BlockedUserOut / StreamHostOut'u türet | `schemas/user.py` |
| 10 | S6 | `DirectSaleSummaryOut` discriminated union yap | `schemas/direct_sale.py` |

### Kısa Vadede (kod kalitesi)

| # | Sorun | Eylem |
|---|-------|-------|
| 11 | S7 | Flutter'a Freezed + json_serializable ekle, tüm modelleri generate et |
| 12 | S8 | `ChatMessage.announcementPayload` sealed class'a çevir |
| 13 | S13 | `UserOut` sadeleştir (core) + `UserProfileOut` (sosyal linkler) |
| 14 | S10 | `ConversationOut` / `MessageRequestOut` ayrı şemalar |
| 15 | S15 | `StreamTokenOut` / `JoinTokenOut` ortak base ile birleştir |

### Orta Vadede (ölçek)

| # | Sorun | Tetikleyici |
|---|-------|-------------|
| 16 | — | ClickHouse Materialized Views | user_events 20M+ satır |
| 17 | — | `direct_messages` partitioning | 50M+ satır |
| 18 | S11 | `AuctionStateOut` discriminated union | Auction logic karmaşıklaşırsa |
| 19 | S12 | `StoryItemOut` discriminated union | Story tipleri çoğalırsa |

### Eskimiş / Gereksiz

| Bulgu | Durum |
|-------|-------|
| Redis Streams (Pub/Sub yerine) | **Tamamlandı** — `xadd` kullanılıyor |
| ClickHouse Dictionaries | **Gereksiz** — LowCardinality zaten var |
| Redis Pool darboğazı | **İzleme** — 440 max conn, Redis 10K limit, sorun yok |
| listings tablosu bölünmesi | **Ertelendi** — ML alanları aktif sorgu yolunda |

---

## Karmaşıklık Özeti

```
PostgreSQL tabloları    : 45
  En büyük tablo        : users (47 kolon), listings (36 kolon)
  PK tipi sorunu        : direct_messages + notifications (int4)
  Sonsuz büyüme         : direct_messages (normal mesajlar hiç silinmiyor)
  God Object            : users (6 sorumluluk), listings (ML + core karışık)

API Şemaları (Pydantic) : 45+ sınıf
  Tipsiz endpoint        : /listings, /listings/{id}, /auth/me, /auth/init (response_model yok)
  Duplicate şemalar      : 4x partial-user (UserOut/StoryAuthorOut/BlockedUserOut/StreamHostOut)
  Union type flat        : DirectSaleSummaryOut (seller+buyer aynı şema)
  Aşırı kullanım         : AuctionStateOut (9 endpoint, 1 şema)

Flutter Modelleri       : 45+ sınıf, 16 dosya
  Freezed                : YOK — tümü manuel fromJson
  Tiplanmamış alan       : ChatMessage.announcementPayload, CallTapSignal.data
  En kompleks model      : ProInsightsData (11 sınıf, 1 ekranda)
  En yayın kullanılan    : ListingFilterState (15 dosyada — iyi soyutlama)

Flutter Ekranlar        : 49 ekran, 259 Dart dosyası
  En kompleks alt modül  : Çağrı altyapısı (lib/call/ — 15 dosya, iyi yapılandırılmış)
  Analitik ekran sayısı  : 10 (pro analytics — oldukça geniş)

En az eforla en fazla kazanç sağlayan 3 hamle:
  1. users tablosunu böl        → God Object çözülür, null alanlar kaybolur
  2. response_model tüm endpointlere → tip güvenliği + Pydantic doğrulama açılır
  3. Freezed ekle (Flutter)     → 45+ manuel fromJson → üretilmiş koda dönüşür
```
