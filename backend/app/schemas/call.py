from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel


class CallParticipantOut(BaseModel):
    user_id: int
    username: str
    avatar: Optional[str] = None
    role: str    # initiator | callee | guest
    status: str  # invited | ringing | joined | left | rejected | timeout | removed

    model_config = {"from_attributes": True}


class InviteToCallRequest(BaseModel):
    invitee_id: int


class InviteToCallResponse(BaseModel):
    participant_id: int
    invitee_id: int
    status: str  # "invited"


class AcceptGroupInviteResponse(BaseModel):
    livekit_token: str
    livekit_url: str
    room_name: str
    participants: List[CallParticipantOut]


class CallOut(BaseModel):
    id: int
    caller_id: int
    callee_id: int
    room_name: str
    status: str
    had_video: bool
    max_participants: int
    started_at: datetime
    accepted_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    duration_seconds: Optional[int] = None

    model_config = {"from_attributes": True}
