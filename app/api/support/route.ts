import { NextResponse } from "next/server";
import { BrevoClient } from "@getbrevo/brevo";

export async function POST(req: Request) {
    try {
        const body = await req.json();
        const { name, email, subject, message } = body;

        // Ensure all fields are provided
        if (!name || !email || !subject || !message) {
            return NextResponse.json(
                { error: "Lütfen tüm alanları doldurun." },
                { status: 400 }
            );
        }

        // Initialize Brevo API client
        const brevo = new BrevoClient({
            apiKey: process.env.BREVO_API_KEY as string,
        });

        // Subject mapping
        const subjectMap: Record<string, string> = {
            general: "Genel Soru / Bilgi Talebi",
            technical: "Teknik Destek",
            report: "Sakıncalı İçerik Şikayeti (UGC)",
            billing: "Ödeme ve Faturalandırma",
            other: "Diğer",
        };

        const displaySubject = subjectMap[subject] || subject;

        await brevo.transactionalEmails.sendTransacEmail({
            subject: `[Destek] ${displaySubject}`,
            htmlContent: `
                <html>
                    <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
                        <h2 style="color: #00B4CC;">Yeni Destek Talebi</h2>
                        <p><strong>Gönderen Adı:</strong> ${name}</p>
                        <p><strong>Gönderen E-posta:</strong> ${email}</p>
                        <p><strong>Konu:</strong> ${displaySubject}</p>
                        <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;" />
                        <p><strong>Mesaj:</strong></p>
                        <div style="background: #f9f9f9; padding: 15px; border-radius: 8px;">
                            ${message.replace(/\n/g, "<br/>")}
                        </div>
                    </body>
                </html>
            `,
            sender: {
                name: "teqlif Destek Formu",
                email: process.env.BREVO_SENDER_EMAIL || "no-reply@teqlif.com",
            },
            replyTo: { email: email, name: name },
            to: [{ email: "destek@teqlif.com", name: "teqlif Destek" }],
        });

        return NextResponse.json({ success: true, message: "Mesajınız başarıyla gönderildi." });
    } catch (error: any) {
        console.error("Brevo API Error:", error.response?.body || error.message || error);
        return NextResponse.json(
            { error: "Mesaj gönderilirken bir hata oluştu." },
            { status: 500 }
        );
    }
}
