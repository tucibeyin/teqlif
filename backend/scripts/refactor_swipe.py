import re

filepath = "backend/app/use_cases/feed/queries/swipe_live_queries.py"
with open(filepath, "r") as f:
    content = f.read()

# Define the class
class_def = """from app.core.uow import AbstractUnitOfWork

class SwipeLiveQueries:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow
"""

lines = content.split('\n')
new_lines = []
inside_func = False
for line in lines:
    if line.startswith("async def ") or line.startswith("def "):
        line = line.replace("(", "(self, ", 1)
        line = re.sub(r",?\s*db:\s*AsyncSession\s*,?", ",", line)
        line = line.replace("(self, ,", "(self,")
        line = line.replace("(self, )", "(self)")
        new_lines.append("    " + line)
        inside_func = True
    elif inside_func and line.startswith("    ") or line == "":
        new_lines.append("    " + line if line != "" else "")
    elif inside_func and not line.startswith("    ") and not line.startswith(")"):
        if not line.startswith("import") and not line.startswith("from") and not line.startswith("logger"):
            new_lines.append("    " + line)
        else:
            new_lines.append(line)
            inside_func = False
    elif line.startswith(") ->"):
        line = re.sub(r",?\s*db:\s*AsyncSession\s*,?", ",", line)
        new_lines.append("    " + line)
    else:
        new_lines.append(line)

content = "\n".join(new_lines)
content = content.replace("db.execute", "self.uow.session.execute")
content = content.replace("db.scalar", "self.uow.session.scalar")

# Fix internal calls
content = re.sub(r"_build_config\((.*?),?\s*db\)", r"self._build_config(\1)", content)
content = re.sub(r"_compute_score\((.*?),?\s*db,?\s*(.*)?\)", r"self._compute_score(\1, \2)", content)

content = content.replace(", db)", ")")

# Inject class definition
imports_end = content.find("logger = logging.getLogger(__name__)")
if imports_end != -1:
    content = content[:imports_end] + "logger = logging.getLogger(__name__)\n\n" + class_def + content[imports_end + len("logger = logging.getLogger(__name__)"):]
else:
    content = class_def + "\n" + content

with open(filepath, "w") as f:
    f.write(content)

print("Refactored swipe_live_queries.py")
