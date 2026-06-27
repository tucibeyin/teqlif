import httpx
from app.config import settings


_WELCOME_COPY = {
    "tr": {
        "subject": "teqlif'e Hoş Geldin, {first_name}! 🎉",
        "hero_title": "Hoş geldin, {first_name}! 🎉",
        "hero_sub": "Canlı açık artırma dünyasına adım attın.<br>Harika fırsatlar seni bekliyor.",
        "intro": "Merhaba <strong style=\"color:#f1f5f9\">{full_name}</strong>,",
        "intro_body": "teqlif'e katıldığın için çok mutluyuz. Artık canlı yayınlarda açık artırmalara katılabilir, favori yayıncıları takip edebilir ve eşsiz ürünlere teklif verebilirsin.",
        "f1_title": "Canlı Yayınlar", "f1_sub": "Yayıncıları keşfet, gerçek zamanlı artırmalara katıl",
        "f2_title": "Anlık Teklifler", "f2_sub": "Saniyeler içinde teklif ver, yarışmayı kazan",
        "f3_title": "Favoriler & Takip", "f3_sub": "Beğendiğin yayıncıları takip et, bildirimleri al",
        "phone_title": "Telefon Doğrulaması",
        "phone_no_body": "Yüksek tutarlı tekliflerde güvenli işlem yapabilmek için telefon numaranızı doğrulamanızı öneririz. Uygulamada <strong style=\"color:#e2e8f0\">Profil → Bilgilerim</strong> ekranından kolayca ekleyebilirsiniz.",
        "phone_yes_body": "Telefon numaranızı kayıt sırasında eklediniz. Güvenli teklif verebilmek için <strong style=\"color:#e2e8f0\">Profil → Bilgilerim</strong> ekranından doğrulamayı tamamlayın.",
        "footer": "Sorularınız için her zaman buradayız.<br>Bize ulaşın: <a href=\"mailto:destek@teqlif.com\" style=\"color:#06b6d4;text-decoration:none\">destek@teqlif.com</a><br><strong style=\"color:#64748b\">teqlif ekibi</strong>",
        "copyright": "© 2025 teqlif · Bu e-postayı almak istemiyorsanız hesap ayarlarınızdan bildirim tercihlerinizi güncelleyebilirsiniz.",
    },
    "en": {
        "subject": "Welcome to teqlif, {first_name}! 🎉",
        "hero_title": "Welcome, {first_name}! 🎉",
        "hero_sub": "You've just stepped into the world of live auctions.<br>Amazing deals are waiting for you.",
        "intro": "Hello <strong style=\"color:#f1f5f9\">{full_name}</strong>,",
        "intro_body": "We're thrilled to have you on teqlif. You can now join live auction streams, follow your favourite hosts, and bid on unique items.",
        "f1_title": "Live Streams", "f1_sub": "Discover hosts and join real-time auctions",
        "f2_title": "Instant Bids", "f2_sub": "Place a bid in seconds and win the competition",
        "f3_title": "Favourites & Follow", "f3_sub": "Follow the hosts you love and get notified",
        "phone_title": "Phone Verification",
        "phone_no_body": "To place high-value bids securely, we recommend verifying your phone number. You can add it anytime from <strong style=\"color:#e2e8f0\">Profile → My Information</strong> in the app.",
        "phone_yes_body": "You added a phone number during sign-up. Complete verification from <strong style=\"color:#e2e8f0\">Profile → My Information</strong> to bid safely.",
        "footer": "We're always here if you need us.<br>Contact us: <a href=\"mailto:destek@teqlif.com\" style=\"color:#06b6d4;text-decoration:none\">destek@teqlif.com</a><br><strong style=\"color:#64748b\">The teqlif team</strong>",
        "copyright": "© 2025 teqlif · You can update your notification preferences in account settings.",
    },
    "ar": {
        "subject": "مرحباً بك في teqlif، {first_name}! 🎉",
        "hero_title": "أهلاً وسهلاً، {first_name}! 🎉",
        "hero_sub": "لقد دخلت عالم المزادات الحية.<br>صفقات رائعة في انتظارك.",
        "intro": "مرحباً <strong style=\"color:#f1f5f9\">{full_name}</strong>،",
        "intro_body": "يسعدنا انضمامك إلى teqlif. يمكنك الآن المشاركة في مزادات البث المباشر ومتابعة مقدمي البث المفضلين لديك وتقديم عروض على منتجات فريدة.",
        "f1_title": "البث المباشر", "f1_sub": "اكتشف المضيفين وانضم إلى المزادات اللحظية",
        "f2_title": "عروض فورية", "f2_sub": "قدّم عرضك في ثوانٍ واربح المنافسة",
        "f3_title": "المفضلة والمتابعة", "f3_sub": "تابع المضيفين الذين تحبهم واحصل على الإشعارات",
        "phone_title": "التحقق من الهاتف",
        "phone_no_body": "لإجراء مزايدات عالية القيمة بأمان، نوصيك بالتحقق من رقم هاتفك. يمكنك إضافته من <strong style=\"color:#e2e8f0\">الملف الشخصي ← معلوماتي</strong> في التطبيق.",
        "phone_yes_body": "أضفت رقم هاتفك أثناء التسجيل. أكمل التحقق من <strong style=\"color:#e2e8f0\">الملف الشخصي ← معلوماتي</strong> لتتمكن من المزايدة بأمان.",
        "footer": "نحن هنا دائماً إذا احتجت إلى مساعدة.<br>تواصل معنا: <a href=\"mailto:destek@teqlif.com\" style=\"color:#06b6d4;text-decoration:none\">destek@teqlif.com</a><br><strong style=\"color:#64748b\">فريق teqlif</strong>",
        "copyright": "© 2025 teqlif · يمكنك تحديث تفضيلات الإشعارات من إعدادات الحساب.",
    },
}


async def send_welcome_email(email: str, full_name: str, has_phone: bool = False, lang: str = "tr") -> None:
    c = _WELCOME_COPY.get(lang, _WELCOME_COPY["tr"])
    first_name = full_name.split()[0] if full_name else full_name
    dir_attr = ' dir="rtl"' if lang == "ar" else ""

    phone_body = c["phone_yes_body"] if has_phone else c["phone_no_body"]
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
                          {c["phone_title"]}
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
  <title>{c["subject"].format(first_name=first_name)}</title>
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
                {c["hero_title"].format(first_name=first_name)}
              </h1>
              <p style="margin:0;font-size:15px;color:#94a3b8;line-height:1.5">
                {c["hero_sub"]}
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
                {c["intro"].format(full_name=full_name)}
              </p>
              <p style="margin:0;font-size:15px;color:#94a3b8;line-height:1.7">
                {c["intro_body"]}
              </p>
            </td>
          </tr>

          <!-- Features -->
          <tr>
            <td style="padding:0 40px 32px">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                {feature_row("🎬", c["f1_title"], c["f1_sub"])}
                {feature_row("🔨", c["f2_title"], c["f2_sub"])}
                {feature_row("⭐", c["f3_title"], c["f3_sub"], bottom_pad="0")}
              </table>
            </td>
          </tr>

          <!-- Phone section -->
          {phone_section}

          <!-- Footer note -->
          <tr>
            <td style="padding:0 40px 40px">
              <p style="margin:0;font-size:13px;color:#475569;line-height:1.6;text-align:center">
                {c["footer"]}
              </p>
            </td>
          </tr>

          <!-- Bottom bar -->
          <tr>
            <td style="background:#060f1e;padding:20px 40px;text-align:center;border-top:1px solid #1e293b">
              <p style="margin:0;font-size:11px;color:#334155;letter-spacing:0.3px">
                {c["copyright"]}
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
        "subject": c["subject"].format(first_name=first_name),
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
) -> None:
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
  <p>Hesabınıza <strong style="font-size:18px;letter-spacing:1px">{phone}</strong> numarası eklendi. Bu numara size ait mi?</p>
  <div style="margin:32px 0;display:flex;gap:12px">
    <a href="{yes_url}" style="display:inline-block;background:#0d9488;color:#fff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px;margin-right:12px">
      ✓ Evet, benimdir
    </a>
    <a href="{no_url}" style="display:inline-block;background:#ef4444;color:#fff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px">
      ✗ Hayır, değil
    </a>
  </div>
  <p style="color:#64748b;font-size:12px">Bu bağlantı <strong>30 dakika</strong> geçerlidir. Bu isteği siz yapmadıysanız yok sayabilirsiniz.</p>
  <p style="color:#475569;font-size:12px;margin-top:16px;border-top:1px solid #1e293b;padding-top:16px">Sorularınız için: <a href="mailto:destek@teqlif.com" style="color:#06b6d4;text-decoration:none">destek@teqlif.com</a></p>
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
            f"<p style='color:#475569;font-size:12px;margin-top:16px;border-top:1px solid #e2e8f0;padding-top:16px'>Sorularınız için: <a href='mailto:destek@teqlif.com' style='color:#0d9488;text-decoration:none'>destek@teqlif.com</a></p>"
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
