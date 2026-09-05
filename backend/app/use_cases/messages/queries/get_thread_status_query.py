from app.core.uow import AbstractUnitOfWork
from app.services.relationship_service import (
    RelationshipStateService,
    _compute_can_call,       # re-export: calls.py ve diğerleri buradan import eder
    _REASON_NO_FOLLOW,       # re-export
    _REASON_PENDING,         # re-export
    _REASON_CALL_DISABLED,   # re-export
)


class GetThreadStatusQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_id: int) -> dict:
        uid_a, uid_b = min(uid, other_id), max(uid, other_id)

        # Redis-first: önce cache'e bak (relationship_service her mutasyonda yazar)
        cached = await RelationshipStateService.get_cached(uid_a, uid_b)
        if cached is not None:
            return cached.to_query_response(uid)

        # Cache miss: DB'den hesapla, cache'e yaz ve döndür
        state = await RelationshipStateService.recompute_and_cache(uid_a, uid_b, self.uow.session)
        return state.to_query_response(uid)
