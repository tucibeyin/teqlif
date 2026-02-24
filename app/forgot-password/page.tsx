"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function ForgotPasswordPage() {
    const router = useRouter();
    const [step, setStep] = useState<"request" | "reset" | "success">("request");
    const [error, setError] = useState("");
    const [loading, setLoading] = useState(false);

    const [email, setEmail] = useState("");
    const [code, setCode] = useState("");
    const [newPassword, setNewPassword] = useState("");

    async function handleRequestReset(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");

        const res = await fetch("/api/auth/forgot-password", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "Bir hata oluştu.");
            return;
        }

        setStep("reset");
    }

    async function handleResetPassword(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");

        const res = await fetch("/api/auth/reset-password", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email, code, newPassword }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "Şifre sıfırlama işlemi başarısız.");
            return;
        }

        setStep("success");
    }

    // ─── Başarı Ekranı ───────────────────────────────────────
    if (step === "success") {
        return (
            <div className="auth-page">
                <div className="auth-card" style={{ textAlign: "center" }}>
                    <div style={{ fontSize: "3.5rem", marginBottom: "1rem" }}>✅</div>
                    <h1 className="auth-title">Şifreniz Sıfırlandı!</h1>
                    <p className="auth-subtitle">
                        Yeni şifrenizle hemen hesabınıza giriş yapabilirsiniz.
                    </p>
                    <div style={{ marginTop: "1.5rem" }}>
                        <Link href="/login" className="btn btn-primary btn-full btn-lg">
                            Giriş Yap
                        </Link>
                    </div>
                </div>
            </div>
        );
    }

    // ─── Şifre Sıfırlama Formu (Kod ve Yeni Şifre) ───────────
    if (step === "reset") {
        return (
            <div className="auth-page">
                <div className="auth-card" style={{ textAlign: "center" }}>
                    <h1 className="auth-title">Şifre Belirleme</h1>
                    <p className="auth-subtitle">
                        <b>{email}</b> adresine gönderdiğimiz doğrulama kodunu ve yeni şifrenizi aşağıya girin.
                    </p>
                    <form className="auth-form" onSubmit={handleResetPassword}>
                        {error && <div className="error-msg">{error}</div>}

                        <div className="form-group" style={{ textAlign: "left" }}>
                            <label htmlFor="code">Doğrulama Kodu</label>
                            <input
                                id="code"
                                type="text"
                                className="input"
                                placeholder="******"
                                required
                                maxLength={6}
                                value={code}
                                onChange={(e) => setCode(e.target.value)}
                                style={{ textAlign: "center", fontSize: "1.5rem", letterSpacing: "5px", padding: "1rem", marginBottom: "1rem" }}
                            />
                        </div>

                        <div className="form-group" style={{ textAlign: "left" }}>
                            <label htmlFor="newPassword">Yeni Şifre</label>
                            <input
                                id="newPassword"
                                type="password"
                                className="input"
                                placeholder="En az 6 karakter"
                                required
                                minLength={6}
                                value={newPassword}
                                onChange={(e) => setNewPassword(e.target.value)}
                            />
                        </div>

                        <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                            {loading ? "Sıfırlanıyor..." : "Şifreyi Kaydet"}
                        </button>
                    </form>
                </div>
            </div>
        );
    }

    // ─── E-posta İstem Formu ─────────────────────────────────
    return (
        <div className="auth-page">
            <div className="auth-card">
                <Link href="/" className="auth-logo">teqlif</Link>
                <h1 className="auth-title">Şifremi Unuttum</h1>
                <p className="auth-subtitle">Hesabınıza kayıtlı e-posta adresinizi girin, size bir sıfırlama kodu gönderelim.</p>

                <form className="auth-form" onSubmit={handleRequestReset}>
                    {error && <div className="error-msg">{error}</div>}
                    <div className="form-group">
                        <label htmlFor="email">E-posta</label>
                        <input
                            id="email"
                            type="email"
                            className="input"
                            placeholder="ornek@email.com"
                            required
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                        />
                    </div>
                    <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                        {loading ? "Gönderiliyor..." : "Doğrulama Kodu Gönder"}
                    </button>
                </form>

                <p className="auth-divider">
                    Şifrenizi hatırladınız mı? <Link href="/login">Giriş yapın</Link>
                </p>
            </div>
        </div>
    );
}
