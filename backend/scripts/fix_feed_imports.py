import os

# fix routers/ads.py
f1 = "backend/app/routers/ads.py"
with open(f1, "r") as f: content = f.read()
content = content.replace("from app.services.feed_service import _get_sponsored_listings\n    return await _get_sponsored_listings(db)", "from app.use_cases.feed.queries.feed_queries import FeedQueries\n    from app.core.uow import SqlAlchemyUnitOfWork\n    return await FeedQueries(SqlAlchemyUnitOfWork(session_factory=lambda: db))._get_sponsored_listings()")
with open(f1, "w") as f: f.write(content)

# fix routers/streams.py
f2 = "backend/app/routers/streams.py"
with open(f2, "r") as f: content = f.read()
content = content.replace("from app.services.feed_service import get_user_interests\n        interests = await get_user_interests(current_user.id, db)", "from app.use_cases.feed.queries.feed_queries import FeedQueries\n        from app.core.uow import SqlAlchemyUnitOfWork\n        interests = await FeedQueries(SqlAlchemyUnitOfWork(session_factory=lambda: db)).get_user_interests(current_user.id)")
with open(f2, "w") as f: f.write(content)

# fix services/swipe_live_service.py (which I am about to eradicate, but let's fix it anyway)
f3 = "backend/app/services/swipe_live_service.py"
with open(f3, "r") as f: content = f.read()
content = content.replace("from app.services.feed_service import get_user_interests", "from app.use_cases.feed.queries.feed_queries import FeedQueries\nfrom app.core.uow import SqlAlchemyUnitOfWork")
content = content.replace("interests = await get_user_interests(user_id, db)", "interests = await FeedQueries(SqlAlchemyUnitOfWork(session_factory=lambda: db)).get_user_interests(user_id)")
with open(f3, "w") as f: f.write(content)

print("Fixed feed imports")
