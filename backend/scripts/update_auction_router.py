import re

filepath = "backend/app/routers/auction.py"
with open(filepath, "r") as f:
    content = f.read()

# Replace imports
content = content.replace(
    "from app.services.auction_service import (",
    "from app.use_cases.auctions.commands.auction_commands import AuctionCommands\n"
    "from app.use_cases.auctions.queries.auction_queries import GetBidsQuery, GetAuctionStateQuery\n"
    "from app.use_cases.auctions.auction_utils import manager, pubsub_listener\n"
    "from app.core.uow import SqlAlchemyUnitOfWork\n"
    "#"
)

content = content.replace("AuctionService(db)", "AuctionCommands(SqlAlchemyUnitOfWork(session_factory=lambda: db))")
content = content.replace("await get_auction_state(stream_id)", "await GetAuctionStateQuery(SqlAlchemyUnitOfWork(session_factory=lambda: None)).execute(stream_id)")
content = content.replace("await get_bids(stream_id, db)", "await GetBidsQuery(SqlAlchemyUnitOfWork(session_factory=lambda: db)).execute(stream_id)")

with open(filepath, "w") as f:
    f.write(content)

print("Updated routers/auction.py")
