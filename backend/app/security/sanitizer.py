# Input Sanitization Middleware for Routes
# Adds protection to existing routes
from fastapi import Request, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware
from app.security.validation import SQLInjectionProtection, SecureInputValidator
from app.security.logging import SecurityLogger, RequestSanitizer
from app.security.middleware import is_ip_blocked

security_logger = SecurityLogger()


class InputSanitizationMiddleware(BaseHTTPMiddleware):
    """Middleware to sanitize and validate all inputs"""
    
    async def dispatch(self, request: Request, call_next):
        # Skip for static files
        if request.url.path.startswith('/static'):
            return await call_next(request)
        
        # Get client IP
        client_ip = RequestSanitizer.get_client_ip(request)
        
        # Check if IP is blocked
        if await is_ip_blocked(client_ip):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your IP has been temporarily blocked"
            )
        
        # Check for SQL injection in query params
        for key, value in request.query_params.items():
            if SQLInjectionProtection.has_sql(str(value)):
                security_logger.injection_attempt(client_ip, str(value))
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid input detected"
                )
        
        # Process request
        response = await call_next(request)
        return response


class RouteInputValidator:
    """Validator for specific routes"""
    
    @staticmethod
    def validate_listing_input(data: dict) -> tuple[bool, str]:
        """Validate listing creation/update input"""
        if 'title' in data:
            valid, err = SecureInputValidator.validate_category(data.get('title', ''))
            if not valid:
                return False, f"Title: {err}"
        
        if 'price' in data and data['price']:
            try:
                price = float(data['price'])
                valid, err = SecureInputValidator.validate_price(price)
                if not valid:
                    return False, f"Price: {err}"
            except ValueError:
                return False, "Invalid price format"
        
        if 'category' in data and data['category']:
            valid, err = SecureInputValidator.validate_category(data['category'])
            if not valid:
                return False, f"Category: {err}"
        
        return True, ""
    
    @staticmethod
    def validate_auction_input(data: dict) -> tuple[bool, str]:
        """Validate auction input"""
        if 'start_price' in data:
            try:
                price = float(data['start_price'])
                valid, err = SecureInputValidator.validate_price(price)
                if not valid:
                    return False, f"Price: {err}"
            except ValueError:
                return False, "Invalid price"
        
        return True, ""
    
    @staticmethod
    def validate_user_input(data: dict) -> tuple[bool, str]:
        """Validate user input"""
        if 'username' in data:
            valid, err = SecureInputValidator.validate_username(data['username'])
            if not valid:
                return False, f"Username: {err}"
        
        if 'phone' in data:
            valid, err = SecureInputValidator.validate_phone(data['phone'])
            if not valid:
                return False, f"Phone: {err}"
        
        return True, ""


def sanitize_search_query(query: str) -> str:
    """Sanitize search query"""
    # Remove potential SQL injection
    query = SQLInjectionProtection.sanitize_for_like(query)
    # Limit length
    query = query[:200]
    # Remove special characters that could be used in attacks
    import re
    query = re.sub(r'[<>\'\";]', '', query)
    return query.strip()


__all__ = ['InputSanitizationMiddleware', 'RouteInputValidator', 'sanitize_search_query']
