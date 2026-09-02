# Privacy & Block — Görev Takibi

> Kaynak plan: `documents/privacy/PLAN.md`

## Çalışma Kuralı

Her adımda sıra şu:
1. Yapılacakları kullanıcıya sun
2. Onay al
3. Implement et
4. Commit et
5. Bu dosyaya kayıt et

---

## Tamamlananlar

### ✅ Task 1.1 — Bug Fix 1 + Karar 7: Story Tray
**Commit:** `6d5ef279`
**Dosya:** `backend/app/services/story_service.py`
**Değişiklikler:**
- `Follow.status == "accepted"` filtresi video ve live sorgularına eklendi (Bug Fix 1)
- `UserBlock` bilateral subquery ile block filtresi her iki sorguya eklendi (Karar 7)
- `from app.models.block import UserBlock` import eklendi

---

## Bekleyenler

- [x] Task 2.1 — Karar 2 (revize): `get_user_profile.py` sosyal link gating | commit `6da253bd`
- [x] Task 2.2 — Karar 2: `auth.py` Redis cache invalidation → **DÜŞÜRÜLDÜ** — profil endpoint'inde Redis cache mevcut değil, her istek zaten DB'den geliyor
- [x] Task 3.1 — Karar 4: `follows.py` follower/following liste gating | commit `b36b79f0`
- [x] Task 3.2 — Karar 4: `error_mapper.dart` FOLLOWERS_LIST_PRIVATE | commit `0945ca31`
- [x] Task 3.3 — Karar 4: `follow_list_view_model.dart` + `follow_list_screen.dart` error handling | commit `5b74a65a`
- [x] Task 4a.1 — Karar 6: `create_offer.py` bilateral block kontrolü → OFFER_FORBIDDEN | commit `bb9f4ce4`
- [x] Task 4a.2 — Karar 6: `error_mapper.dart` OFFER_FORBIDDEN + ARB (4 dil) | commit `bb9f4ce4`
- [x] Task 4a.3 — Karar 6: seller_is_blocked UI alanı → **DÜŞÜRÜLDÜ** — BE enforce eder, UI error mapper ile yakalar (Task 3.3 pattern)
- [x] Task 4a.4 — Karar 6: `listing_detail_screen.dart` → **DÜŞÜRÜLDÜ** — yukarıdaki kararla gereksiz
- [x] Task 4b.1 — Karar 6: `search.py` refactor → use_cases/search/queries/ + ilan ve stream block filtreleri kaldırıldı | commit `10b8277a`
- [x] Task 4c.1 — Karar 6: `chat.py` WS join bilateral auto-mute | commit `616ea057`
- [x] Task 4d.1 — Karar 6: `get_viewers.py` is_muted per viewer + `_ViewersBottomSheet` badge + ARB streamViewerMuted (4 dil) | commit `59634f36`
- [x] Task 4e.1 — Karar 8: `misc_queries.py` GetFollowedLiveStreams block filtresi → DÜŞÜRÜLDÜ (zaten yok); GetActiveStreams'den _apply_block_filter kaldırıldı | commit `6563f218`
- [x] Task 5.0 — Karar 3: Alembic migration `zzzzl_msg_threads_01` | commit `64804dd4`
- [x] Task 5.1 — Karar 3: `message_thread.py` model | commit `64804dd4`
- [x] Task 5.2 — Karar 3: `models/__init__.py` import | commit `64804dd4`
- [x] Task 5.3 — Karar 3: `send_direct_message.py` + `send_media_message_command.py` is_request mantığı | commit `64804dd4`
- [x] Task 5.4 — Karar 3: `follows.py` follow accept → thread taşıma | commit `64804dd4`
- [x] Task 5.5 — Karar 3: `auth.py` is_private→False bulk taşıma | commit `64804dd4`
- [x] Task 5.6 — Karar 3: `messages.py` refactor (thin router) + 3 yeni endpoint (requests list/accept/decline) | commit `64804dd4`
- [x] Task 5.7 — Karar 3: notification → is_new_request kontrolü ile bildirim gönderilmez | commit `64804dd4`
- [x] Task 5.E — Media hata kodları: ARB (4 dil) + error_mapper.dart + _uploadMedia() fix | commit `64804dd4`
- [x] Task 5.B — Option B schema: migration+model is_request→status('pending'/'accepted'/'declined')+initiator_id; auto-accept; soft decline; notifMsgRequestAccepted ARB (4 dil) | commit `b5ab3245`
- [x] Task 5.8 — Karar 3: `_RequestsListTab` ConsumerWidget + `RequestsTabViewModel` + `getMessageRequests()` + inner TabController (MVVM, NeverScrollableScrollPhysics, DRY helpers) + ARB (4 dil) | commit `f86d382f`
- [x] Task 5.9 — Karar 3: thread status endpoint + request banner | commit `c7761ed7`
  - BE bug fix: list_message_requests_query (initiator_id != uid)
  - BE bug fix: get_conversations_query (initiator's pending visible in inbox)
  - BE: GetThreadStatusQuery + GET /api/messages/thread/{id}/status
  - BE: auto-accept notification body preview
  - Flutter: DirectChatRequestNotifier (AutoDisposeFamilyAsyncNotifier, keyed by otherUserId)
  - Flutter: _RequestBanner — receiver: Accept/Decline; initiator: informational label
  - Flutter: NotificationService — getThreadStatus / acceptMessageRequest / declineMessageRequest
  - ARB (4 dil): msgReqBannerReceiver, msgReqBannerInitiator, msgReqBannerAccept, msgReqBannerDecline
- [x] Task 5.10 — Karar 3: requestCount in MessagesUiState + outer tab badge | commit `0c424730`
  - MessagesUiState.requestCount: int
  - MessagesScreenViewModel: parallel Future.wait for notif count + requests list
  - WS messageStream listener eklendi (yeni istek gelince count güncellenir)
  - Dış Mesajlar sekmesi: requestCount > 0 ise kırmızı nokta badge
- [x] Task 6.1 — Karar 5: `storage_service.dart` privacy banner key | commit `c8e5bf09`
- [x] Task 6.2 — Karar 5: `profile_screen.dart` banner logic | commit `665d11b3`
  - ProfileUiState.showPrivacyBanner: bool
  - ProfileViewModel.load(): async storage check + is_private koşulu
  - ProfileViewModel.dismissPrivacyBanner(): storage yaz + state kapat
  - _PrivacyBanner ConsumerWidget: header altında, kendi profili + public hesap + ilk gösterim
  - ARB (4 dil): privacyBannerTitle, privacyBannerDesc, privacyBannerAction
- [x] ARB — privacyBannerTitle/Desc/Action 4 dil (Task 6.2 ile tamamlandı)
