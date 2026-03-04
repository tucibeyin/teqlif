"use client";
import { useState } from "react";
import Link from "next/link";
import { signIn } from "next-auth/react";
import { useRouter } from "next/navigation";

export default function RegisterPage() {
    const router = useRouter();
    const [error, setError] = useState("");
    const [step, setStep] = useState<"register" | "verify" | "success">("register");
    const [userEmail, setUserEmail] = useState("");
    const [userPass, setUserPass] = useState("");
    const [verifyCode, setVerifyCode] = useState("");
    const [loading, setLoading] = useState(false);
    const [userName, setUserName] = useState("");
    const [eulaAccepted, setEulaAccepted] = useState(false);

    async function handleRegister(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");
        const fd = new FormData(e.currentTarget);

        const name = fd.get("name") as string;
        const email = fd.get("email") as string;
        const password = fd.get("password") as string;
        const confirm = fd.get("confirm") as string;

        if (password !== confirm) {
            setError("Şifreler eşleşmiyor.");
            setLoading(false);
            return;
        }

        // 1. Kayıt API
        const res = await fetch("/api/auth/register", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                name,
                email,
                phone: fd.get("phone"),
                password,
            }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "Kayıt işlemi başarısız.");
            return;
        }

        if (data.pendingVerification) {
            setUserEmail(data.email);
            // No need to save userPass if we don't auto-login
            setUserName(data.name.split(" ")[0]);
            setStep("verify");
        } else {
            // Fallback for immediate success
            setUserName(data.name.split(" ")[0]);
            setStep("success");
        }
    }

    async function handleVerify(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");

        const res = await fetch("/api/auth/verify-email", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email: userEmail, code: verifyCode }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "Doğrulama başarısız.");
            return;
        }

        setStep("success");
    }

    // ─── Başarı Ekranı ───────────────────────────────────────
    if (step === "success") {
        return (
            <div className="auth-page">
                <div className="auth-card" style={{ textAlign: "center" }}>
                    <div style={{ fontSize: "3.5rem", marginBottom: "1rem" }}>🎉</div>
                    <h1 className="auth-title">Hoş Geldin, {userName}!</h1>
                    <p className="auth-subtitle">
                        E-postanız başarıyla doğrulandı.
                    </p>
                    <div style={{
                        background: "var(--primary-50)",
                        border: "1.5px solid var(--primary-100)",
                        borderRadius: "var(--radius-lg)",
                        padding: "1rem",
                        marginTop: "1.5rem",
                        color: "var(--primary-dark)",
                        fontSize: "0.9rem",
                    }}>
                        ✅ Hesabınız aktif! Artık ilan vermeye ve teqlif yapmaya hazırsınız. Giriş yaparak işlemlere başlayabilirsiniz.
                    </div>
                    <div style={{ marginTop: "1.5rem", display: "flex", gap: "0.75rem", justifyContent: "center", flexWrap: "wrap" }}>
                        <Link href="/login" className="btn btn-primary">
                            Giriş Yap
                        </Link>
                    </div>
                </div>
            </div>
        );
    }

    // ─── Doğrulama Ekranı ────────────────────────────────────
    if (step === "verify") {
        return (
            <div className="auth-page">
                <div className="auth-card" style={{ textAlign: "center" }}>
                    <div style={{ fontSize: "3.5rem", marginBottom: "1rem" }}>✉️</div>
                    <h1 className="auth-title">E-postanızı Doğrulayın</h1>
                    <p className="auth-subtitle">
                        <b>{userEmail}</b> adresine 6 haneli bir doğrulama kodu gönderdik. Lütfen kodu aşağıya girin.
                    </p>

                    <form className="auth-form" onSubmit={handleVerify}>
                        {error && <div className="error-msg">{error}</div>}
                        <div className="form-group" style={{ textAlign: "left" }}>
                            <label htmlFor="code">Doğrulama Kodu</label>
                            <input
                                id="code"
                                name="code"
                                type="text"
                                className="input"
                                placeholder="******"
                                required
                                maxLength={6}
                                value={verifyCode}
                                onChange={(e) => setVerifyCode(e.target.value)}
                                style={{ textAlign: "center", fontSize: "1.5rem", letterSpacing: "5px", padding: "1rem" }}
                            />
                        </div>
                        <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                            {loading ? "Doğrulanıyor..." : "Hesabı Onayla"}
                        </button>
                    </form>
                </div>
            </div>
        );
    }

    // ─── Kayıt Formu ─────────────────────────────────────────
    return (
        <div className="auth-page">
            <div className="auth-card">
                <Link href="/" className="auth-logo">teqlif</Link>
                <h1 className="auth-title">Üye Ol</h1>
                <p className="auth-subtitle">Hemen ücretsiz hesap oluşturun</p>

                <form className="auth-form" onSubmit={handleRegister}>
                    {error && <div className="error-msg">{error}</div>}
                    <div className="form-group">
                        <label htmlFor="name">Ad Soyad</label>
                        <input id="name" name="name" type="text" className="input" placeholder="Adınız Soyadınız" required />
                    </div>
                    <div className="form-group">
                        <label htmlFor="email">E-posta</label>
                        <input id="email" name="email" type="email" className="input" placeholder="ornek@email.com" required />
                    </div>
                    <div className="form-group">
                        <label htmlFor="phone">
                            Telefon <span style={{ color: "var(--text-muted)", fontWeight: 400 }}>(İsteğe bağlı)</span>
                        </label>
                        <input id="phone" name="phone" type="tel" className="input" placeholder="05XX XXX XX XX" />
                    </div>
                    <div className="form-group">
                        <label htmlFor="password">Şifre</label>
                        <input id="password" name="password" type="password" className="input" placeholder="En az 6 karakter" required minLength={6} />
                    </div>
                    <div className="form-group">
                        <label htmlFor="confirm">Şifre Tekrar</label>
                        <input id="confirm" name="confirm" type="password" className="input" placeholder="Şifrenizi tekrar girin" required />
                    </div>
                    <div className="form-group" style={{ display: "flex", alignItems: "flex-start", gap: "0.5rem", marginTop: "1rem" }}>
                        <input
                            id="eula"
                            name="eula"
                            type="checkbox"
                            checked={eulaAccepted}
                            onChange={(e) => setEulaAccepted(e.target.checked)}
                            style={{ marginTop: "0.25rem", width: "1.25rem", height: "1.25rem", cursor: "pointer" }}
                            required
                        />
                        <label htmlFor="eula" style={{ fontSize: "0.85rem", color: "var(--text-secondary)", cursor: "pointer", lineHeight: "1.4" }}>
                            <Link href="/terms" target="_blank" className="font-semibold text-[var(--primary)] hover:underline">Kullanım Koşullarını ve EULA&apos;yı</Link> kabul ediyorum. Sakıncalı içerik ve taciz edici davranışlara tolerans gösterilmeyeceğini, ihlal durumunda hesabımın 24 saat içinde kapatılabileceğini biliyorum.
                        </label>
                    </div>
                    <button type="submit" id="register-btn" className="btn btn-primary btn-full btn-lg" disabled={loading || !eulaAccepted} style={{ marginTop: "1.5rem" }}>
                        {loading ? "Hesap oluşturuluyor..." : "🚀 Üye Ol"}
                    </button>
                </form>

                <p className="auth-divider">
                    Zaten hesabınız var mı? <Link href="/login">Giriş yapın</Link>
                </p>
            </div>
        </div>
    );
}
