export async function sendEmail({
    to,
    subject,
    htmlContent,
}: {
    to: string;
    subject: string;
    htmlContent: string;
}) {
    const apiKey = process.env.BREVO_API_KEY;
    if (!apiKey) {
        console.error("BREVO_API_KEY is not defined in environment variables.");
        throw new Error("Missing email API settings");
    }

    const response = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
            "accept": "application/json",
            "api-key": apiKey,
            "content-type": "application/json",
        },
        body: JSON.stringify({
            sender: { name: "teqlif.com", email: "noreply@teqlif.com" },
            to: [{ email: to }],
            subject: subject,
            htmlContent: htmlContent,
        }),
    });

    if (!response.ok) {
        const errorData = await response.text();
        console.error("Failed to send email via Brevo:", errorData);
        throw new Error("Failed to send email");
    }

    return response.json();
}

export async function sendVerificationEmail(to: string, code: string) {
    const subject = "Teqlif - E-posta Doğrulama Kodunuz";
    const htmlContent = `
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #eee; border-radius: 8px; overflow: hidden;">
      <div style="background-color: #00B4CC; padding: 20px; text-align: center;">
        <h1 style="color: white; margin: 0;">teqlif</h1>
      </div>
      <div style="padding: 30px; text-align: center; color: #333;">
        <h2 style="color: #008FA3;">Hoş Geldiniz!</h2>
        <p style="font-size: 16px; line-height: 1.5;">Hesabınızı başarıyla oluşturduk. Teqlif'te avantajlı alışveriş deneyimine başlamadan önce, lütfen aşağıdaki 6 haneli doğrulama kodunu uygulamaya girerek e-postanızı doğrulayın:</p>
        <div style="background-color: #f4f7fa; padding: 20px; margin: 30px 0; border-radius: 8px; border: 1px dashed #00b4cc;">
          <span style="font-size: 32px; font-weight: bold; color: #00B4CC; letter-spacing: 5px;">${code}</span>
        </div>
        <p style="font-size: 14px; color: #777;">Bu kod 15 dakika boyunca geçerlidir. Lütfen kimseyle paylaşmayın.</p>
      </div>
      <div style="background-color: #f9f9f9; padding: 15px; text-align: center; font-size: 12px; color: #aaa;">
        © 2026 teqlif. Tüm hakları saklıdır.
      </div>
    </div>
  `;
    return sendEmail({ to, subject, htmlContent });
}

export async function sendPasswordResetEmail(to: string, code: string) {
    const subject = "Teqlif - Şifre Sıfırlama Kodunuz";
    const htmlContent = `
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #eee; border-radius: 8px; overflow: hidden;">
      <div style="background-color: #00B4CC; padding: 20px; text-align: center;">
        <h1 style="color: white; margin: 0;">teqlif</h1>
      </div>
      <div style="padding: 30px; text-align: center; color: #333;">
        <h2 style="color: #008FA3;">Şifre Sıfırlama İsteği</h2>
        <p style="font-size: 16px; line-height: 1.5;">Teqlif şifrenizi sıfırlamak için bir talepte bulundunuz. Hesabınıza yeniden erişebilmek için lütfen aşağıdaki 6 haneli güvenlik kodunu kullanın:</p>
        <div style="background-color: #f4f7fa; padding: 20px; margin: 30px 0; border-radius: 8px; border: 1px dashed #00b4cc;">
          <span style="font-size: 32px; font-weight: bold; color: #00B4CC; letter-spacing: 5px;">${code}</span>
        </div>
        <p style="font-size: 14px; color: #777;">Bu kod 15 dakika boyunca geçerlidir. Eğer bu işlemi siz yapmadıysanız lütfen bu e-postayı dikkate almayın.</p>
      </div>
      <div style="background-color: #f9f9f9; padding: 15px; text-align: center; font-size: 12px; color: #aaa;">
        © 2026 teqlif. Tüm hakları saklıdır.
      </div>
    </div>
  `;
    return sendEmail({ to, subject, htmlContent });
}
