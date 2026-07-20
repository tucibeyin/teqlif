import sys

def replace_in_file(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    # Replace specific lines
    content = content.replace("from app.services.user_service import UserService", 
"""from app.use_cases.users.commands.block_commands import BlockUserCommand, UnblockUserCommand
from app.use_cases.users.queries.get_blocked_users import GetBlockedUsersQuery
from app.use_cases.users.queries.get_user_profile import GetUserProfileQuery
from app.core.uow import SqlAlchemyUnitOfWork""")
    
    content = content.replace("return await UserService(db).get_profile(username, current_user)", "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await GetUserProfileQuery(uow).execute(username, current_user)")
    content = content.replace("return await UserService(db).list_blocked(current_user)", "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await GetBlockedUsersQuery(uow).execute(current_user)")
    content = content.replace("return await UserService(db).block(username, current_user)", "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await BlockUserCommand(uow).execute(username, current_user)")
    content = content.replace("return await UserService(db).unblock(username, current_user)", "uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)\n    return await UnblockUserCommand(uow).execute(username, current_user)")

    with open(filepath, "w") as f:
        f.write(content)

if __name__ == "__main__":
    replace_in_file("backend/app/routers/users.py")
    print("Replaced!")
