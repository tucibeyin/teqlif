---
description: commit and push all changes to GitHub
---

// turbo-all

1. Stage all changes, commit with a descriptive message, and push to GitHub:
```bash
cd /Users/tucibeyin/Desktop/teqlif && git add -A && git commit -m "${COMMIT_MESSAGE}" && git push origin main
```

Use a meaningful commit message that summarizes what changed. If no specific message is provided, use a short descriptive summary of the files changed (e.g. "feat: add login page" or "fix: correct bid validation logic").

2. Confirm push was successful by checking exit code and output.
