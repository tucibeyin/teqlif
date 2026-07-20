import os

paths = [
    "backend/app/services/like_service.py",
    "backend/app/use_cases/streams/commands/force_close_stream.py",
    "backend/app/use_cases/streams/commands/cohost_commands.py",
    "backend/app/use_cases/auctions/commands/auction_commands.py",
    "backend/app/use_cases/streams/commands/misc_commands.py",
    "backend/app/core/hype_manager.py",
    "backend/app/routers/wallet.py",
    "backend/app/routers/chat.py",
    "backend/app/worker.py",
]

for p in paths:
    if os.path.exists(p):
        with open(p, "r") as f:
            content = f.read()
        content = content.replace("from app.services.chat_service import publish_chat", "from app.use_cases.chat.chat_utils import publish_chat")
        content = content.replace("from app.services.chat_service import chat_pubsub_listener, moderation_pubsub_listener", "from app.use_cases.chat.chat_utils import chat_pubsub_listener, moderation_pubsub_listener")
        content = content.replace("from app.services.chat_service import (", "from app.use_cases.chat.chat_utils import (")
        with open(p, "w") as f:
            f.write(content)

print("Replaced chat imports")
