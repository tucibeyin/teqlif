import httpx
from app.config import settings


async def send_verification_code(email: str, full_name: str, code: str) -> None:
    payload = {
        "sender": {
            "name": settings.brevo_sender_name,
            "email": settings.brevo_sender_email,
        },
        "to": [{"email": email, "name": full_name}],
        "subject": "Teqlif - E-posta Doğrulama Kodu",
        "htmlContent": (
            f"<p>Merhaba <strong>{full_name}</strong>,</p>"
            f"<p>Teqlif hesabınızı doğrulamak için aşağıdaki kodu kullanın:</p>"
            f"<h2 style='letter-spacing:6px;color:#0d9488;'>{code}</h2>"
            f"<p>Bu kod <strong>10 dakika</strong> geçerlidir.</p>"
            f"<p>Bu isteği siz yapmadıysanız bu e-postayı yok sayabilirsiniz.</p>"
        ),
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(
            "https://api.brevo.com/v3/smtp/email",
            json=payload,
            headers={
                "api-key": settings.brevo_api_key,
                "Content-Type": "application/json",
            },
            timeout=10.0,
        )
        response.raise_for_status()
