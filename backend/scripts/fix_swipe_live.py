with open("backend/app/services/swipe_live_service.py", "r") as f:
    content = f.read()

content = content.replace("streams = await StreamService(db).get_active_streams(user_id)", 
"""from app.use_cases.streams.queries.misc_queries import GetActiveStreamsQuery
    from app.core.uow import SqlAlchemyUnitOfWork
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    streams = await GetActiveStreamsQuery(uow).execute(user_id)""")

with open("backend/app/services/swipe_live_service.py", "w") as f:
    f.write(content)
