from app.core.uow import AbstractUnitOfWork
from app.services.relationship_service import (
    RelationshipStateService,
    _compute_can_call,       # re-export: calls.py ve diğerleri buradan import eder
    _REASON_NO_FOLLOW,       # re-export
    _REASON_PENDING,         # re-export
    _REASON_CALL_DISABLED,   # re-export
    _REASON_USER_BUSY,       # re-export
)


async def _overlay_busy(response: dict, other_id: int) -> dict:
    """can_call True ise hedefin anlık call presence'ını kontrol eder.

    Busy durumu statik önbelleğe yazılmaz — SRE-108 Cache Poisoning düzeltmesi.
    """
    from app.services.call_presence import is_busy as _is_busy
    if response.get("can_call") and await _is_busy(other_id):
        response = {**response, "can_call": False, "can_call_reason": _REASON_USER_BUSY}
    return response


class GetThreadStatusQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_id: int) -> dict:
        uid_a, uid_b = min(uid, other_id), max(uid, other_id)

        # Redis-first: önce cache'e bak (relationship_service her mutasyonda yazar)
        cached = await RelationshipStateService.get_cached(uid_a, uid_b)
        if cached is not None:
            return await _overlay_busy(cached.to_query_response(uid), other_id)

        # Cache miss: DB'den hesapla, cache'e yaz ve döndür
        state = await RelationshipStateService.recompute_and_cache(uid_a, uid_b, self.uow.session)
        return await _overlay_busy(state.to_query_response(uid), other_id)
