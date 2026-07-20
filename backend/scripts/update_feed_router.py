import re

filepath = "backend/app/routers/feed.py"
with open(filepath, "r") as f:
    content = f.read()

content = content.replace(
    "from app.services.feed_service import get_personalized_feed, get_foryou_feed, get_mixed_recent_feed",
    "from app.use_cases.feed.queries.feed_queries import FeedQueries\n"
    "from app.core.uow import SqlAlchemyUnitOfWork"
)
content = content.replace(
    "await get_personalized_feed(user_id, page, seed, db)",
    "await FeedQueries(SqlAlchemyUnitOfWork(session_factory=lambda: db)).get_personalized_feed(user_id, page, seed)"
)
content = content.replace(
    "await get_mixed_recent_feed(user_id, page, db)",
    "await FeedQueries(SqlAlchemyUnitOfWork(session_factory=lambda: db)).get_mixed_recent_feed(user_id, page)"
)
content = content.replace(
    "await get_foryou_feed(current_user.id, page, db)",
    "await FeedQueries(SqlAlchemyUnitOfWork(session_factory=lambda: db)).get_foryou_feed(current_user.id, page)"
)

with open(filepath, "w") as f:
    f.write(content)

print("Updated routers/feed.py")
