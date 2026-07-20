import re

filepath = "backend/app/use_cases/feed/queries/feed_queries.py"
with open(filepath, "r") as f:
    content = f.read()

# Remove the class definition from the middle
class_def = """class FeedQueries:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow
"""
content = content.replace(class_def, "")

# Insert it before the first method (which is async def get_user_interests)
insertion_point = content.find("    async def get_user_interests")
content = content[:insertion_point] + class_def + "\n" + content[insertion_point:]

with open(filepath, "w") as f:
    f.write(content)

print("Fixed syntax in feed_queries.py")
