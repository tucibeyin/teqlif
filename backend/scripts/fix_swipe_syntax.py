import re

filepath = "backend/app/use_cases/feed/queries/swipe_live_queries.py"
with open(filepath, "r") as f:
    content = f.read()

# Remove the class definition from the middle
class_def = """from app.core.uow import AbstractUnitOfWork

class SwipeLiveQueries:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow
"""
content = content.replace(class_def, "")
content = content.replace("from app.core.uow import AbstractUnitOfWork\n\nclass SwipeLiveQueries:\n    def __init__(self, uow: AbstractUnitOfWork):\n        self.uow = uow", "")

# Insert it before the first method (which is async def get_swipe_live_config)
insertion_point = content.find("    async def get_swipe_live_config")
content = content[:insertion_point] + class_def + "\n" + content[insertion_point:]

with open(filepath, "w") as f:
    f.write(content)

print("Fixed syntax in swipe_live_queries.py")
