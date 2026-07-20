import re

filepath = "backend/app/use_cases/auctions/commands/auction_commands.py"
with open(filepath, "r") as f:
    content = f.read()

# Remove the pubsub listener, manager, etc. since they are now in auction_utils.py
content = re.sub(r"(?s)class AuctionConnectionManager:.*?manager = AuctionConnectionManager\(\)", "", content)
content = re.sub(r"(?s)async def pubsub_listener\(\):.*?await ws_manager\.subscribe\(\"auction_broadcast\", _on_message\)", "", content)
content = re.sub(r"(?s)async def publish_auction.*?await ws_manager\.publish\(\"auction_broadcast\", \"global\", payload\)", "", content)
content = re.sub(r"(?s)async def _log_fraud_attempt.*?pass", "", content)
content = re.sub(r"def fmt_price.*?replace\(\"X\", \"\.\"\)", "", content)
content = re.sub(r"def auction_key.*?return f\"auction:\{stream_id\}\"", "", content)
content = re.sub(r"(?s)async def get_bids.*?return out", "", content)
content = re.sub(r"(?s)async def get_auction_state.*?return \{.*?\}", "", content)
content = re.sub(r"(?s)async def get_state\(stream_id: int\) -> dict:.*?return \{.*?\}", "", content)

# Change class AuctionService: to class AuctionCommands:
content = content.replace("class AuctionService:", "class AuctionCommands:")
content = content.replace("def __init__(self, db: AsyncSession):", "def __init__(self, uow):")
content = content.replace("self.db = db", "self.uow = uow")
content = content.replace("self.db.", "self.uow.session.")
content = content.replace("db=self.db", "db=self.uow.session")

# Add imports at the top
imports = """
from app.core.uow import AbstractUnitOfWork
from app.use_cases.auctions.auction_utils import manager, _log_fraud_attempt, fmt_price, auction_key, publish_auction, _require_host
"""
content = imports + content

with open(filepath, "w") as f:
    f.write(content)

print("Refactored auction commands!")
