from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from jose import jwt
from app.core.log_context import user_id_var

class LogContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        user_id = None
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
            try:
                # Fast parse without verification just to extract user_id for logs
                payload = jwt.decode(token, options={"verify_signature": False})
                user_id = str(payload.get("sub"))
            except Exception:
                pass
        
        # Set contextvar (defaults to None if not extracted, but filter sets "guest")
        token = user_id_var.set(user_id)
        try:
            response = await call_next(request)
            return response
        finally:
            user_id_var.reset(token)
