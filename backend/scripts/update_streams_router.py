import re

with open("backend/app/routers/streams.py", "r") as f:
    content = f.read()

# Replace imports
content = content.replace("from app.services.stream_service import StreamService", "")
content = content.replace("from app.use_cases.streams.commands.start_stream import StartStreamCommand", 
"""from app.use_cases.streams.commands.start_stream import StartStreamCommand
from app.use_cases.streams.commands.join_stream import JoinStreamCommand
from app.use_cases.streams.commands.lifecycle_commands import ConfirmLiveCommand, CancelPendingStreamCommand
from app.use_cases.streams.commands.misc_commands import EndStreamCommand, UpdateThumbnailCommand
from app.use_cases.streams.commands.cohost_commands import InviteCohostCommand, AcceptCohostInviteCommand, RemoveCohostCommand, LeaveCohostCommand
from app.use_cases.streams.queries.get_viewers import GetViewersQuery
from app.use_cases.streams.queries.misc_queries import GetFollowedLiveStreamsQuery, GetActiveStreamsQuery
from app.core.uow import SqlAlchemyUnitOfWork""")

# Confirm Live
content = re.sub(
    r"return await StreamService\(db\)\.confirm_live\(stream_id, current_user, background_tasks\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await ConfirmLiveCommand(uow).execute(stream_id, current_user, background_tasks)",
    content
)

# Cancel Pending
content = re.sub(
    r"await StreamService\(db\)\.cancel_pending\(stream_id, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    await CancelPendingStreamCommand(uow).execute(stream_id, current_user)",
    content
)

# End
content = re.sub(
    r"return await StreamService\(db\)\.end\(stream_id, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await EndStreamCommand(uow).execute(stream_id, current_user)",
    content
)

# Get Viewers
content = re.sub(
    r"return await StreamService\(db\)\.get_viewers\(stream_id, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await GetViewersQuery(uow).execute(stream_id, current_user)",
    content
)

# Join
content = re.sub(
    r"return await StreamService\(db\)\.join\(stream_id, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await JoinStreamCommand(uow).execute(stream_id, current_user)",
    content
)

# Update Thumbnail
content = re.sub(
    r"return await StreamService\(db\)\.update_thumbnail\(stream_id, current_user, file\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await UpdateThumbnailCommand(uow).execute(stream_id, current_user, file)",
    content
)

# Invite Cohost
content = re.sub(
    r"return await StreamService\(db\)\.invite_cohost\(stream_id, body\.target_username, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await InviteCohostCommand(uow).execute(stream_id, body.target_username, current_user)",
    content
)

# Accept Cohost
content = re.sub(
    r"return await StreamService\(db\)\.accept_cohost_invite\(stream_id, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await AcceptCohostInviteCommand(uow).execute(stream_id, current_user)",
    content
)

# Remove Cohost
content = re.sub(
    r"return await StreamService\(db\)\.remove_cohost\(stream_id, body\.target_username, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await RemoveCohostCommand(uow).execute(stream_id, body.target_username, current_user)",
    content
)

# Leave Cohost
content = re.sub(
    r"return await StreamService\(db\)\.leave_cohost\(stream_id, current_user\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await LeaveCohostCommand(uow).execute(stream_id, current_user)",
    content
)

# Get Followed
content = re.sub(
    r"return await StreamService\(db\)\.get_followed_live_streams\(current_user\.id\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await GetFollowedLiveStreamsQuery(uow).execute(current_user.id)",
    content
)

# Get Recommended (We'll just map it to ActiveStreams for now to delete the service)
content = re.sub(
    r"return await StreamService\(db\)\.get_recommended_streams\(current_user\.id\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await GetActiveStreamsQuery(uow).execute(current_user.id)",
    content
)

# Get Active
content = re.sub(
    r"return await StreamService\(db\)\.get_active_streams\(current_user_id\)",
    "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await GetActiveStreamsQuery(uow).execute(current_user_id)",
    content
)

with open("backend/app/routers/streams.py", "w") as f:
    f.write(content)

print("Updated streams.py")
