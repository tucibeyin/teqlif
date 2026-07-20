import re

filepath = "backend/app/use_cases/feed/queries/feed_queries.py"
with open(filepath, "r") as f:
    content = f.read()

# Define the class
class_def = """from app.core.uow import AbstractUnitOfWork

class FeedQueries:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow
"""

# We need to indent everything that defines a function and change signature.
lines = content.split('\n')
new_lines = []
inside_func = False
for line in lines:
    if line.startswith("async def ") or line.startswith("def "):
        # Add self to signature
        line = line.replace("(", "(self, ", 1)
        # Remove db: AsyncSession if present
        line = re.sub(r",?\s*db:\s*AsyncSession\s*,?", ",", line)
        line = line.replace("(self, ,", "(self,")
        line = line.replace("(self, )", "(self)")
        new_lines.append("    " + line)
        inside_func = True
    elif inside_func and line.startswith("    ") or line == "":
        new_lines.append("    " + line if line != "" else "")
    elif inside_func and not line.startswith("    ") and not line.startswith(")"):
        # Probably a global variable or import in the middle of nowhere? Let's just indent it if it's not an import.
        if not line.startswith("import") and not line.startswith("from"):
            new_lines.append("    " + line)
        else:
            new_lines.append(line)
            inside_func = False
    elif line.startswith(") ->"):
        # multiline function def
        line = re.sub(r",?\s*db:\s*AsyncSession\s*,?", ",", line)
        new_lines.append("    " + line)
    else:
        new_lines.append(line)

content = "\n".join(new_lines)
content = content.replace("db.execute", "self.uow.session.execute")
content = content.replace("db.scalar", "self.uow.session.scalar")
content = content.replace("await db.", "await self.uow.session.")

# Handle internal calls like get_user_interests(..., db) -> self.get_user_interests(...)
content = re.sub(r"get_user_interests\(([^,]+)(?:,\s*db)?\)", r"self.get_user_interests(\1)", content)
content = re.sub(r"_score_and_rank\((.*?),?\s*db,?\s*(.*)?\)", r"self._score_and_rank(\1, \2)", content)
content = re.sub(r"_popular_feed\((.*?),?\s*db,?\s*(.*)?\)", r"self._popular_feed(\1, \2)", content)
content = re.sub(r"_mark_impressions\((.*?),?\s*db\)", r"self._mark_impressions(\1)", content)
content = re.sub(r"_compute_foryou_ids\((.*?),?\s*db,?\s*(.*)?\)", r"self._compute_foryou_ids(\1, \2)", content)
content = re.sub(r"_get_user_top_categories\((.*?),?\s*db,?\s*(.*)?\)", r"self._get_user_top_categories(\1, \2)", content)
content = re.sub(r"_get_sponsored_listings\((.*?),?\s*db,?\s*(.*)?\)", r"self._get_sponsored_listings(\1, \2)", content)
content = re.sub(r"_fetch_interest_items\((.*?),?\s*db,?\s*(.*)?\)", r"self._fetch_interest_items(\1, \2)", content)

# Remove the explicit db parameter from internal calls
content = content.replace(", db)", ")")
content = content.replace(", db,", ",")
content = content.replace("(db,", "(")

# Add class definition after imports
imports_end = content.find("\n\nlogger = logging.getLogger(__name__)")
if imports_end != -1:
    content = content[:imports_end] + "\n\n" + class_def + content[imports_end:]
else:
    content = class_def + "\n" + content

with open(filepath, "w") as f:
    f.write(content)

print("Refactored feed_queries.py")
