import contextvars
from typing import Optional

# Global context variable to hold the user_id for the current request
user_id_var: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("user_id", default=None)
