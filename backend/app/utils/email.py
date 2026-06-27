import httpx
from app.config import settings


async def send_phone_verification_email(
    email: str,
    full_name: str,
    phone: str,
    yes_url: str,
    no_url: str,
) -> None:
    masked = phone[:3] + "***" + phone[-2:] if len(phone) > 5 else "***"
    payload = {
        "sender": {
            "name": settings.brevo_sender_name,
            "email": settings.brevo_sender_email,
        },
        "to": [{"email": email, "name": full_name}],
        "subject": "teqlif - Telefon Numaranızı Onaylayın",
        "htmlContent": f"""
<div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;background:#0f172a;color:#f1f5f9;border-radius:16px;padding:32px">
  <h2 style="color:#0d9488;margin-top:0">Telefon Numarası Doğrulama</h2>
  <p>Merhaba <strong>{full_name}</strong>,</p>
  <p>Hesabınıza <strong>{masked}</strong> numarası eklendi. Bu numara size ait mi?</p>
  <div style="margin:32px 0;display:flex;gap:12px">
    <a href="{yes_url}" style="display:inline-block;background:#0d9488;color:#fff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px;margin-right:12px">
      ✓ Evet, benimdir
    </a>
    <a href="{no_url}" style="display:inline-block;background:#ef4444;color:#fff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px">
      ✗ Hayır, değil
    </a>
  </div>
  <p style="color:#64748b;font-size:12px">Bu bağlantı <strong>30 dakika</strong> geçerlidir. Bu isteği siz yapmadıysanız yok sayabilirsiniz.</p>
</div>
""",
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


async def send_verification_code(email: str, full_name: str, code: str, *, has_phone: bool = False) -> None:
    phone_note = (
        "<p style='margin-top:20px;padding:12px 16px;background:#1e293b;border-left:3px solid #0d9488;"
        "border-radius:4px;color:#94a3b8;font-size:13px'>"
        "📱 Kayıt sırasında telefon numarası girdiniz. Hesabınıza giriş yaptıktan sonra "
        "<strong style='color:#f1f5f9'>Profil → Bilgilerim</strong> ekranından telefonunuzu doğrulayabilirsiniz.</p>"
    ) if has_phone else ""

    payload = {
        "sender": {
            "name": settings.brevo_sender_name,
            "email": settings.brevo_sender_email,
        },
        "to": [{"email": email, "name": full_name}],
        "subject": "teqlif - E-posta Doğrulama Kodu",
        "htmlContent": (
            f"<p>Merhaba <strong>{full_name}</strong>,</p>"
            f"<p>teqlif hesabınızı doğrulamak için aşağıdaki kodu kullanın:</p>"
            f"<h2 style='letter-spacing:6px;color:#0d9488;'>{code}</h2>"
            f"<p>Bu kod <strong>10 dakika</strong> geçerlidir.</p>"
            f"{phone_note}"
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
