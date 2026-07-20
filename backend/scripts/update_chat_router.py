import re

filepath = "backend/app/routers/chat.py"
with open(filepath, "r") as f:
    content = f.read()

content = content.replace("from app.services.chat_service import ChatService", "from app.use_cases.chat.commands.chat_commands import ChatCommands")
content = content.replace("chat_svc = ChatService()", "chat_svc = ChatCommands()")

with open(filepath, "w") as f:
    f.write(content)

print("Updated routers/chat.py")
