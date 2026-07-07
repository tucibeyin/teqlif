import httpx
import json
import os

_ARB_CACHE: dict = {}      # lang -> dict
_ARB_MTIME: dict = {}     # lang -> float (last modified time)

def _get_t(lang: str) -> dict:
    try:
        base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        arb_path = os.path.join(base_dir, "mobile", "lib", "l10n", f"app_{lang}.arb")
        mtime = os.path.getmtime(arb_path)
        if lang not in _ARB_CACHE or _ARB_MTIME.get(lang) != mtime:
            with open(arb_path, 'r', encoding='utf-8') as f:
                _ARB_CACHE[lang] = json.load(f)
            _ARB_MTIME[lang] = mtime
    except Exception:
        if lang != "tr":
            return _get_t("tr")
        return {}
    return _ARB_CACHE[lang]


from app.config import settings


async def send_welcome_email(email: str, full_name: str, has_phone: bool = False, lang: str = "tr") -> None:
    t = _get_t(lang)
    first_name = full_name.split()[0] if full_name else full_name
    dir_attr = ' dir="rtl"' if lang == "ar" else ""

    phone_body = t.get("emailWelcomePhoneYesBody", "") if has_phone else t.get("emailWelcomePhoneNoBody", "")
    border_side = "border-right" if lang == "ar" else "border-left"

    phone_section = f"""
        <tr>
          <td style="padding:0 40px 32px">
            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                   style="background:#0f172a;border-radius:12px;border:1px solid #1e3a4a">
              <tr>
                <td style="padding:20px 24px">
                  <table cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="vertical-align:top;padding-right:14px;font-size:22px;line-height:1">📱</td>
                      <td>
                        <p style="margin:0 0 6px;color:#06b6d4;font-size:14px;font-weight:700;letter-spacing:0.3px">
                          {t.get("emailWelcomePhoneTitle", "")}
                        </p>
                        <p style="margin:0;color:#94a3b8;font-size:13px;line-height:1.6">
                          {phone_body}
                        </p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>"""

    def feature_row(icon: str, title: str, sub: str, bottom_pad: str = "12px") -> str:
        return f"""
                <tr>
                  <td style="padding-bottom:{bottom_pad}">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0"
                           style="background:#0f172a;border-radius:12px;{border_side}:3px solid #06b6d4">
                      <tr>
                        <td style="padding:16px 20px">
                          <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                              <td style="vertical-align:middle;padding-right:14px;font-size:20px;line-height:1">{icon}</td>
                              <td>
                                <p style="margin:0 0 3px;color:#f1f5f9;font-size:14px;font-weight:700">{title}</p>
                                <p style="margin:0;color:#64748b;font-size:13px">{sub}</p>
                              </td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>"""

    html = f"""<!DOCTYPE html>
<html lang="{lang}"{dir_attr}>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>{t.get("emailWelcomeSub", "").format(first_name=first_name)}</title>
</head>
<body style="margin:0;padding:0;background:#060f1e;font-family:'Helvetica Neue',Arial,sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#060f1e;padding:40px 16px">
    <tr>
      <td align="center">
        <table width="560" cellpadding="0" cellspacing="0" border="0"
               style="max-width:560px;width:100%;background:#0c1a2e;border-radius:20px;
                      overflow:hidden;border:1px solid #1e3a4a">

          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#0c2a3e 0%,#0a1f30 50%,#061524 100%);
                       padding:40px 40px 32px;text-align:center">
              <p style="margin:0 0 24px;font-size:28px;font-weight:900;letter-spacing:-0.5px;color:#06b6d4">
                teqlif
              </p>
              <h1 style="margin:0 0 10px;font-size:26px;font-weight:800;color:#f1f5f9;
                          line-height:1.2;letter-spacing:-0.3px">
                {t.get("emailWelcomeHeroTitle", "").format(first_name=first_name)}
              </h1>
              <p style="margin:0;font-size:15px;color:#94a3b8;line-height:1.5">
                {t.get("emailWelcomeHeroSub", "")}
              </p>
            </td>
          </tr>

          <!-- Divider accent -->
          <tr>
            <td style="height:3px;background:linear-gradient(90deg,#06b6d4,#0891b2,#06b6d4)"></td>
          </tr>

          <!-- Intro -->
          <tr>
            <td style="padding:36px 40px 28px">
              <p style="margin:0 0 16px;font-size:15px;color:#cbd5e1;line-height:1.7">
                {t.get("emailWelcomeIntro", "").format(full_name=full_name)}
              </p>
              <p style="margin:0;font-size:15px;color:#94a3b8;line-height:1.7">
                {t.get("emailWelcomeIntroBody", "")}
              </p>
            </td>
          </tr>

          <!-- Features -->
          <tr>
            <td style="padding:0 40px 32px">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                {feature_row("🎬", t.get("emailWelcomeF1Title", ""), t.get("emailWelcomeF1Sub", ""))}
                {feature_row("🔨", t.get("emailWelcomeF2Title", ""), t.get("emailWelcomeF2Sub", ""))}
                {feature_row("⭐", t.get("emailWelcomeF3Title", ""), t.get("emailWelcomeF3Sub", ""), bottom_pad="0")}
              </table>
            </td>
          </tr>

          <!-- Phone section -->
          {phone_section}

          <!-- Footer note -->
          <tr>
            <td style="padding:0 40px 40px">
              <p style="margin:0;font-size:13px;color:#475569;line-height:1.6;text-align:center">
                {t.get("emailWelcomeFooter", "")}
              </p>
            </td>
          </tr>

          <!-- Bottom bar -->
          <tr>
            <td style="background:#060f1e;padding:20px 40px;text-align:center;border-top:1px solid #1e293b">
              <p style="margin:0;font-size:11px;color:#334155;letter-spacing:0.3px">
                {t.get("emailWelcomeCopyright", "")}
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

    payload = {
        "sender": {"name": settings.brevo_sender_name, "email": settings.brevo_sender_email},
        "to": [{"email": email, "name": full_name}],
        "subject": t.get("emailWelcomeSub", "").format(first_name=first_name),
        "htmlContent": html,
    }
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "https://api.brevo.com/v3/smtp/email",
            json=payload,
            headers={"api-key": settings.brevo_api_key, "Content-Type": "application/json"},
            timeout=10.0,
        )
        response.raise_for_status()


async def send_phone_verification_email(
    email: str,
    full_name: str,
    phone: str,
    yes_url: str,
    no_url: str,
    lang: str = "tr",
) -> None:
    t = _get_t(lang)
    payload = {
        "sender": {
            "name": settings.brevo_sender_name,
            "email": settings.brevo_sender_email,
        },
        "to": [{"email": email, "name": full_name}],
        "subject": t.get('emailPhoneVerifySub', ''),
        "htmlContent": f"""
<div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;background:#0f172a;color:#f1f5f9;border-radius:16px;padding:32px">
  <h2 style="color:#0d9488;margin-top:0">{t.get('emailPhoneVerifyTitle', '')}</h2>
  <p>{t.get('emailHello', '')} <strong>{full_name}</strong>,</p>
  <p>{t.get('emailPhoneAdded', '').format(phone=phone)}</p>
  <div style="margin:32px 0;display:flex;gap:12px">
    <a href="{yes_url}" style="display:inline-block;background:#0d9488;color:#fff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px;margin-right:12px">
      {t.get('emailYesMine', '')}
    </a>
    <a href="{no_url}" style="display:inline-block;background:#ef4444;color:#fff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px">
      {t.get('emailNoNotMine', '')}
    </a>
  </div>
  <p style="color:#64748b;font-size:12px">{t.get('emailLinkValid30m', '')}</p>
  <p style="color:#475569;font-size:12px;margin-top:16px;border-top:1px solid #1e293b;padding-top:16px">{t.get('emailSupport', '')} <a href="mailto:destek@teqlif.com" style="color:#06b6d4;text-decoration:none">destek@teqlif.com</a></p>
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


async def send_verification_code(email: str, full_name: str, code: str, *, has_phone: bool = False, lang: str = "tr") -> None:
    t = _get_t(lang)
    phone_note = (
        f"<p style='margin-top:20px;padding:12px 16px;background:#1e293b;border-left:3px solid #0d9488;"
        f"border-radius:4px;color:#94a3b8;font-size:13px'>"
        f"{t.get('emailPhoneNote', '')}</p>"
    ) if has_phone else ""

    payload = {
        "sender": {
            "name": settings.brevo_sender_name,
            "email": settings.brevo_sender_email,
        },
        "to": [{"email": email, "name": full_name}],
        "subject": t.get('emailVerifySub', ''),
        "htmlContent": (
            f"<p>{t.get('emailHello', '')} <strong>{full_name}</strong>,</p>"
            f"<p>{t.get('emailVerifyBody', '')}</p>"
            f"<h2 style='letter-spacing:6px;color:#0d9488;'>{code}</h2>"
            f"<p>{t.get('emailCodeValid10m', '')}</p>"
            f"{phone_note}"
            f"<p>Bu isteği siz yapmadıysanız bu e-postayı yok sayabilirsiniz.</p>"
            f"<p style='color:#475569;font-size:12px;margin-top:16px;border-top:1px solid #e2e8f0;padding-top:16px'>{t.get('emailSupport', '')} <a href='mailto:destek@teqlif.com' style='color:#0d9488;text-decoration:none'>destek@teqlif.com</a></p>"
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


async def send_reset_password_email(email: str, full_name: str, code: str, lang: str = "tr") -> None:
    t = _get_t(lang)
    dir_attr = " dir='rtl'" if lang == "ar" else ""
    
    payload = {
        "sender": {
            "name": settings.brevo_sender_name,
            "email": settings.brevo_sender_email,
        },
        "to": [{"email": email, "name": full_name}],
        "subject": t.get("emailWelcomeSub", ""),
        "htmlContent": (
            f"<div{dir_attr}>"
            f"<p>{t.get("emailResetGreeting", "").format(full_name=full_name)}</p>"
            f"<p>{t.get("emailResetBody", "")}</p>"
            f"<h2 style='letter-spacing:6px;color:#0d9488;'>{code}</h2>"
            f"<p>{t.get("emailCodeValid10m", "")}</p>"
            f"<p>{t.get("emailIgnoreIfNotYou", "")}</p>"
            f"<p style='color:#475569;font-size:12px;margin-top:16px;border-top:1px solid #e2e8f0;padding-top:16px'>{t.get("emailResetFooter", "")}</p>"
            f"</div>"
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
