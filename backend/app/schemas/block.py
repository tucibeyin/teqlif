from pydantic import BaseModel
from app.schemas.user import UserMiniOut


class BlockedUserOut(UserMiniOut):
    pass


class BlockStatusOut(BaseModel):
    is_blocked: bool
