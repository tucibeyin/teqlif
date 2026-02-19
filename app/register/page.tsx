"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { signIn } from "next-auth/react";

export default function RegisterPage() {
    const router = useRouter();
    const [error, setError] = useState("");
    const [loading, setLoading] = useState(false);

    async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");
        const fd = new FormData(e.currentTarget);

        const password = fd.get("password") as string;
        const confirm = fd.get("confirm") as string;

        if (password !== confirm) {
            setError("Şifreler eşleşmiyor.");
            setLoading(false);
            return;
        }

        const res = await fetch("/api/auth/register", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                name: fd.get("name"),
                email: fd.get("email"),
                phone: fd.get("phone"),
                password,
            }),
        });

        const data = await res.json();

        if (!res.ok) {
            setError(data.error || "Kayıt işlemi başarısız.");
            setLoading(false);
            return;
        }

        // Auto-login
        await signIn("credentials", {
            email: fd.get("email"),
            password,
            redirect: false,
        });

        router.push("/");
        router.refresh();
    }

    return (
        <div className="auth-page">
            <div className="auth-card">
                <Link href="/" className="auth-logo">teqlif</Link>
                <h1 className="auth-title">Üye Ol</h1>
                <p className="auth-subtitle">Hemen ücretsiz hesap oluşturun</p>

                <form className="auth-form" onSubmit={handleSubmit}>
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
                        <label htmlFor="phone">Telefon <span className="text-muted">(İsteğe bağlı)</span></label>
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
                    <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                        {loading ? "Hesap oluşturuluyor..." : "Üye Ol"}
                    </button>
                </form>

                <p className="auth-divider">
                    Zaten hesabınız var mı? <Link href="/login">Giriş yapın</Link>
                </p>
            </div>
        </div>
    );
}
