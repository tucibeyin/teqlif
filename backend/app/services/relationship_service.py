"""
RelationshipStateService — iki kullanıcı arasındaki ilişki durumunun
tek hesaplama ve dağıtım noktası.

Her follow/thread/is_private/call_allowed değişikliği buradan geçer.
Sonuç Redis'e yazılır; her iki tarafa 'relationship_changed' WS eventi yayılır.

Kural: başka hiçbir dosyada can_call veya relationship broadcast mantığı olmaz.
"""
import asyncio
import json
from dataclasses import dataclass, field
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from sqlalchemy import or_, and_

from app.models.follow import Follow
from app.models.block import UserBlock
from app.models.message_thread import MessageThread
from app.services.dm_broadcast import broadcast_dm
from app.utils.redis_client import get_redis

# ── Reason sabitleri (backward compat için buradan import edilebilir) ─────────
_REASON_NO_FOLLOW     = "no_follow"
_REASON_PENDING       = "pending"
_REASON_CALL_DISABLED = "call_disabled"
_REASON_USER_BUSY     = "user_busy"
_REASON_BLOCKED       = "blocked"
_REASON_DECLINED      = "declined"

_REL_TTL = 3600  # Redis TTL: 1 saat


# ── Pure hesaplama fonksiyonu ─────────────────────────────────────────────────

def _compute_can_message(
    sender_is_initiator: bool,
    target_follows_sender: bool,
    thread_status: Optional[str],
) -> tuple[bool, Optional[str]]:
    """
    sender → target mesaj gönderebilir mi?
    declined dışında her durumda izin var.
    declined: reddeden her zaman yazabilir; reddedilen yalnızca target follows sender ise.
    """
    if thread_status != "declined":
        return True, None
    if not sender_is_initiator:
        return True, None
    return (True, None) if target_follows_sender else (False, _REASON_DECLINED)


def _compute_can_call(
    viewer_follows_target: bool,
    target_follows_viewer: bool,
    thread_status: Optional[str],
    call_allowed: bool,
) -> tuple[bool, Optional[str]]:
    """
    caller=viewer, callee=target perspektifinden can_call hesaplar.
    Returns (can_call, reason) — reason is None when can_call=True.
    """
    if viewer_follows_target and target_follows_viewer:
        return True, None
    if target_follows_viewer and not viewer_follows_target:
        return True, None
    if viewer_follows_target and not target_follows_viewer:
        if thread_status == "accepted":
            return (True, None) if call_allowed else (False, _REASON_CALL_DISABLED)
        if thread_status == "pending":
            return False, _REASON_PENDING
        if thread_status == "declined":
            return False, _REASON_DECLINED
        return False, _REASON_NO_FOLLOW
    if thread_status == "accepted":
        return (True, None) if call_allowed else (False, _REASON_CALL_DISABLED)
    if thread_status == "pending":
        return False, _REASON_PENDING
    if thread_status == "declined":
        return False, _REASON_DECLINED
    return False, _REASON_NO_FOLLOW


# ── State nesnesi ─────────────────────────────────────────────────────────────

@dataclass
class PairRelationshipState:
    uid_a: int          # always min(u1, u2)
    uid_b: int          # always max(u1, u2)

    a_follows_b: bool
    b_follows_a: bool
    thread_status: Optional[str]   # None | pending | accepted | declined
    initiator_id: Optional[int]
    call_allowed: bool

    can_call_ab: bool              # uid_a → uid_b arayabilir mi
    reason_ab: Optional[str]
    perm_editable_for_a: bool      # call toggle bar göster/gizle

    can_call_ba: bool              # uid_b → uid_a arayabilir mi
    reason_ba: Optional[str]
    perm_editable_for_b: bool

    can_message_ab: bool           # uid_a → uid_b mesaj gönderebilir mi
    reason_msg_ab: Optional[str]
    can_message_ba: bool           # uid_b → uid_a mesaj gönderebilir mi
    reason_msg_ba: Optional[str]

    def payload_for(self, viewer_id: int) -> dict:
        """viewer'a gönderilecek 'relationship_changed' WS payload'ı."""
        is_a = viewer_id == self.uid_a
        peer_id = self.uid_b if is_a else self.uid_a
        return {
            "type": "relationship_changed",
            "peer_id": peer_id,
            "thread_status": self.thread_status,
            "is_initiator": (self.initiator_id == viewer_id) if self.initiator_id is not None else False,
            "can_call": self.can_call_ab if is_a else self.can_call_ba,
            "can_call_reason": self.reason_ab if is_a else self.reason_ba,
            "call_allowed": self.call_allowed,
            "call_permission_editable": self.perm_editable_for_a if is_a else self.perm_editable_for_b,
            "can_message": self.can_message_ab if is_a else self.can_message_ba,
            "can_message_reason": self.reason_msg_ab if is_a else self.reason_msg_ba,
        }

    def to_query_response(self, uid: int) -> dict:
        """GetThreadStatusQuery API response formatına dönüştür."""
        is_a = uid == self.uid_a
        return {
            "status": self.thread_status,
            "is_initiator": (self.initiator_id == uid) if self.initiator_id is not None else False,
            "can_call": self.can_call_ab if is_a else self.can_call_ba,
            "can_call_reason": self.reason_ab if is_a else self.reason_ba,
            "call_allowed": self.call_allowed,
            "call_permission_editable": self.perm_editable_for_a if is_a else self.perm_editable_for_b,
            "can_message": self.can_message_ab if is_a else self.can_message_ba,
            "can_message_reason": self.reason_msg_ab if is_a else self.reason_msg_ba,
        }

    def to_redis_dict(self) -> dict:
        return {
            "uid_a": self.uid_a,
            "uid_b": self.uid_b,
            "a_follows_b": int(self.a_follows_b),
            "b_follows_a": int(self.b_follows_a),
            "thread_status": self.thread_status or "",
            "initiator_id": self.initiator_id or 0,
            "call_allowed": int(self.call_allowed),
            "can_call_ab": int(self.can_call_ab),
            "reason_ab": self.reason_ab or "",
            "perm_editable_for_a": int(self.perm_editable_for_a),
            "can_call_ba": int(self.can_call_ba),
            "reason_ba": self.reason_ba or "",
            "perm_editable_for_b": int(self.perm_editable_for_b),
            "can_message_ab": int(self.can_message_ab),
            "reason_msg_ab": self.reason_msg_ab or "",
            "can_message_ba": int(self.can_message_ba),
            "reason_msg_ba": self.reason_msg_ba or "",
        }


def _redis_key(uid_a: int, uid_b: int) -> str:
    return f"rel:{min(uid_a, uid_b)}:{max(uid_a, uid_b)}"


def _build_state(
    uid_a: int,
    uid_b: int,
    a_follows_b: bool,
    b_follows_a: bool,
    thread_status: Optional[str],
    initiator_id: Optional[int],
    call_allowed: bool,
) -> PairRelationshipState:
    can_call_ab, reason_ab = _compute_can_call(a_follows_b, b_follows_a, thread_status, call_allowed)
    can_call_ba, reason_ba = _compute_can_call(b_follows_a, a_follows_b, thread_status, call_allowed)

    a_is_initiator = initiator_id == uid_a if initiator_id is not None else False
    b_is_initiator = initiator_id == uid_b if initiator_id is not None else False
    can_message_ab, reason_msg_ab = _compute_can_message(a_is_initiator, b_follows_a, thread_status)
    can_message_ba, reason_msg_ba = _compute_can_message(b_is_initiator, a_follows_b, thread_status)

    # Toggle görünürlüğü: acceptor'ın initiator'ı takip edip etmediğine göre
    # Aynı değer her iki tarafa da yansıtılır (ortak bir kavram)
    if thread_status == "accepted" and initiator_id is not None:
        editable = not b_follows_a if initiator_id == uid_a else not a_follows_b
    else:
        editable = False

    return PairRelationshipState(
        uid_a=uid_a, uid_b=uid_b,
        a_follows_b=a_follows_b, b_follows_a=b_follows_a,
        thread_status=thread_status, initiator_id=initiator_id, call_allowed=call_allowed,
        can_call_ab=can_call_ab, reason_ab=reason_ab, perm_editable_for_a=editable,
        can_call_ba=can_call_ba, reason_ba=reason_ba, perm_editable_for_b=editable,
        can_message_ab=can_message_ab, reason_msg_ab=reason_msg_ab,
        can_message_ba=can_message_ba, reason_msg_ba=reason_msg_ba,
    )


# ── Servis ────────────────────────────────────────────────────────────────────

class RelationshipStateService:

    @staticmethod
    def compute(
        uid_a: int,
        uid_b: int,
        a_follows_b: bool,
        b_follows_a: bool,
        thread_status: Optional[str],
        initiator_id: Optional[int],
        call_allowed: bool,
    ) -> PairRelationshipState:
        """Pure hesaplama — DB/Redis erişimi yok. Değerler zaten eldeyse kullan."""
        return _build_state(uid_a, uid_b, a_follows_b, b_follows_a, thread_status, initiator_id, call_allowed)

    @staticmethod
    async def recompute_and_cache(
        uid_a: int,
        uid_b: int,
        session: AsyncSession,
    ) -> PairRelationshipState:
        """DB'den tüm inputları okur, hesaplar, call presence ekler, Redis'e yazar."""
        a, b = min(uid_a, uid_b), max(uid_a, uid_b)

        follows_ab = await session.scalar(
            select(Follow).where(Follow.follower_id == a, Follow.followed_id == b, Follow.status == "accepted")
        )
        follows_ba = await session.scalar(
            select(Follow).where(Follow.follower_id == b, Follow.followed_id == a, Follow.status == "accepted")
        )
        thread = await session.scalar(
            select(MessageThread).where(MessageThread.user_a_id == a, MessageThread.user_b_id == b)
        )

        is_blocked = await session.scalar(
            select(UserBlock).where(
                or_(
                    and_(UserBlock.blocker_id == a, UserBlock.blocked_id == b),
                    and_(UserBlock.blocker_id == b, UserBlock.blocked_id == a),
                )
            ).limit(1)
        )

        state = _build_state(
            uid_a=a, uid_b=b,
            a_follows_b=follows_ab is not None,
            b_follows_a=follows_ba is not None,
            thread_status=thread.status if thread else None,
            initiator_id=thread.initiator_id if thread else None,
            call_allowed=thread.call_allowed if thread else False,
        )

        # Block override: engel varsa her iki yönde de arama ve mesajlaşma kapalı
        if is_blocked:
            state.can_call_ab = False
            state.reason_ab = _REASON_BLOCKED
            state.can_call_ba = False
            state.reason_ba = _REASON_BLOCKED
            state.can_message_ab = False
            state.reason_msg_ab = _REASON_BLOCKED
            state.can_message_ba = False
            state.reason_msg_ba = _REASON_BLOCKED

        # Call presence override: hedef aramadaysa can_call → False + user_busy
        from app.services.call_presence import is_busy as _is_busy
        if state.can_call_ab and await _is_busy(b):
            state.can_call_ab = False
            state.reason_ab = _REASON_USER_BUSY
        if state.can_call_ba and await _is_busy(a):
            state.can_call_ba = False
            state.reason_ba = _REASON_USER_BUSY

        await RelationshipStateService.cache(state)
        return state

    @staticmethod
    async def cache(state: PairRelationshipState) -> None:
        """State'i Redis'e yazar."""
        r = await get_redis()
        await r.set(_redis_key(state.uid_a, state.uid_b), json.dumps(state.to_redis_dict()), ex=_REL_TTL)

    @staticmethod
    async def get_cached(uid_a: int, uid_b: int) -> Optional[PairRelationshipState]:
        """Redis'ten okur. Cache miss'te None döner."""
        r = await get_redis()
        raw = await r.get(_redis_key(min(uid_a, uid_b), max(uid_a, uid_b)))
        if not raw:
            return None
        try:
            d = json.loads(raw)
            return PairRelationshipState(
                uid_a=d["uid_a"], uid_b=d["uid_b"],
                a_follows_b=bool(d["a_follows_b"]),
                b_follows_a=bool(d["b_follows_a"]),
                thread_status=d["thread_status"] or None,
                initiator_id=d["initiator_id"] or None,
                call_allowed=bool(d["call_allowed"]),
                can_call_ab=bool(d["can_call_ab"]),
                reason_ab=d["reason_ab"] or None,
                perm_editable_for_a=bool(d["perm_editable_for_a"]),
                can_call_ba=bool(d["can_call_ba"]),
                reason_ba=d["reason_ba"] or None,
                perm_editable_for_b=bool(d["perm_editable_for_b"]),
                can_message_ab=bool(d.get("can_message_ab", 1)),
                reason_msg_ab=d.get("reason_msg_ab") or None,
                can_message_ba=bool(d.get("can_message_ba", 1)),
                reason_msg_ba=d.get("reason_msg_ba") or None,
            )
        except Exception:
            return None

    @staticmethod
    def broadcast(state: PairRelationshipState) -> None:
        """Her iki tarafa 'relationship_changed' WS event'i gönder (fire-and-forget)."""
        asyncio.create_task(broadcast_dm(state.uid_a, state.payload_for(state.uid_a)))
        asyncio.create_task(broadcast_dm(state.uid_b, state.payload_for(state.uid_b)))

    @staticmethod
    async def invalidate(uid_a: int, uid_b: int) -> None:
        """Cache'i temizle — sonraki GetThreadStatusQuery DB'den yeniden hesaplar."""
        r = await get_redis()
        await r.delete(_redis_key(min(uid_a, uid_b), max(uid_a, uid_b)))
