import re

filepath = "backend/app/use_cases/chat/commands/chat_commands.py"
with open(filepath, "r") as f:
    content = f.read()

content = re.sub(r"def chat_key.*?return f\"chat:\{stream_id\}:messages\"", "", content, flags=re.DOTALL)
content = re.sub(r"async def publish_chat.*?await ws_manager\.publish\(_CHAT_CHANNEL, f\"chat:\{stream_id\}\", payload\)", "", content, flags=re.DOTALL)
content = re.sub(r"async def update_viewer_count.*?exc_info=True,\s*\)", "", content, flags=re.DOTALL)
content = re.sub(r"async def chat_pubsub_listener.*?await stream_listener\(_CHAT_CHANNEL, _on_message\)", "", content, flags=re.DOTALL)
content = re.sub(r"async def moderation_pubsub_listener.*?await stream_listener\(MOD_CHANNEL, _on_message\)", "", content, flags=re.DOTALL)
content = re.sub(r"async def _dispatch_mod_event.*?f\"chat:\{sid\}\", \{\"type\": WS\.MOD_DEMOTED, \"user_id\": uid\}\)", "", content, flags=re.DOTALL)

content = content.replace("class ChatService:", "class ChatCommands:\n    def __init__(self, uow=None):\n        self.uow = uow")

imports = """
from app.use_cases.chat.chat_utils import chat_key, publish_chat, update_viewer_count
from app.core.uow import AbstractUnitOfWork
"""
content = imports + content

with open(filepath, "w") as f:
    f.write(content)

print("Refactored chat commands")
