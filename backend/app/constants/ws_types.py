"""
WebSocket mesaj type sabitleri.

Bu modül tüm WS type string'lerinin tek kaynağıdır (single source of truth).
Backend servisleri bu sabitleri import ederek magic string kullanımını ortadan kaldırır.

Eşdeğer sabitler:
  • JS  → frontend/static/js/chat.js ve auction.js içindeki string literaller
  • Dart → mobile/lib/widgets/chat_panel.dart ve auction_panel.dart içindeki string literaller
"""

# ── Chat ─────────────────────────────────────────────────────────────────────
MESSAGE          = "message"
SYSTEM_JOIN      = "system_join"
HISTORY          = "history"
VIEWER_COUNT     = "viewer_count"
STREAM_ENDED     = "stream_ended"
MUTED            = "muted"
UNMUTED          = "unmuted"
KICKED           = "kicked"
HOST_PIN         = "host_pin"
STREAM_LIKE      = "stream_like"

# ── Moderasyon ────────────────────────────────────────────────────────────────
MOD_STATUS        = "mod_status"        # WS bağlantısında mevcut mod durumu (bağlanan kullanıcıya)
MOD_PROMOTED      = "mod_promoted"
MOD_PROMOTED_SELF = "mod_promoted_self"
MOD_DEMOTED       = "mod_demoted"
MOD_DEMOTED_SELF  = "mod_demoted_self"

# ── Co-host ───────────────────────────────────────────────────────────────────
COHOST_INVITE   = "cohost_invite"
COHOST_ACCEPTED = "cohost_accepted"
COHOST_REMOVED  = "cohost_removed"

# ── Açık Artırma ──────────────────────────────────────────────────────────────
AUCTION_STATE                = "state"
BUY_IT_NOW_REQUESTED         = "buy_it_now_requested"
BUY_IT_NOW_REJECTED          = "buy_it_now_rejected"
AUCTION_ENDED_BY_BUY_IT_NOW  = "auction_ended_by_buy_it_now"

# ── Balina Radarı ─────────────────────────────────────────────────────────────
WHALE_ALERT = "WHALE_ALERT"  # Sadece yayın sahibine (host) gönderilir

# ── Canlı Hediye ──────────────────────────────────────────────────────────────
GIFT = "gift"  # Tüm odaya broadcast — gönderen, gift_name, cost

# ── Hype Meter (Heyecan Ölçer) ───────────────────────────────────────────────
HYPE_UPDATE = "hype_update"   # Tüm odaya: {"type": "hype_update", "score": 85}
HYPE_ALERT  = "hype_alert"    # Sadece host'a: {"type": "hype_alert", "message": "..."}

# ── Grup Sesli/Görüntülü Arama ────────────────────────────────────────────────
# Davete çağrılan kişiye
CALL_GROUP_INVITE         = "call_group_invite"
# Odadakilere — "X kişiye davet gönderildi" bildirimi
CALL_PARTICIPANT_INVITED  = "call_participant_invited"
# Odadakilere — katılımcı aramaya dahil oldu
CALL_PARTICIPANT_JOINED   = "call_participant_joined"
# Odadakilere — katılımcı aramayı kapattı
CALL_PARTICIPANT_LEFT     = "call_participant_left"
# Daveti başlatana — davetli kişi reddetti
CALL_PARTICIPANT_REJECTED = "call_participant_rejected"
# Daveti başlatana — davetli kişi 30s içinde yanıt vermedi
CALL_PARTICIPANT_TIMEOUT  = "call_participant_timeout"
# Odadakilere + çıkarılan kişiye — initiator tarafından çıkarıldı
CALL_PARTICIPANT_REMOVED  = "call_participant_removed"
