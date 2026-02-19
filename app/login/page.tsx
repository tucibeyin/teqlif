"use client";
import { useState } from "react";
import Link from "next/link";
import { signIn } from "next-auth/react";
import { useRouter } from "next/navigation";

export default function LoginPage() {
    const router = useRouter();
    const [error, setError] = useState("");
    const [loading, setLoading] = useState(false);

    async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");
        const fd = new FormData(e.currentTarget);

        const result = await signIn("credentials", {
            email: fd.get("email"),
            password: fd.get("password"),
            redirect: false,
        });

        setLoading(false);
        if (result?.error) {
            setError("Email veya şifre hatalı.");
        } else {
            router.push("/");
            router.refresh();
        }
    }

    return (
        <div className="auth-page">
            <div className="auth-card">
                <Link href="/" className="auth-logo">teqlif</Link>
                <h1 className="auth-title">Giriş Yap</h1>
                <p className="auth-subtitle">Hesabınıza giriş yapın</p>

                <form className="auth-form" onSubmit={handleSubmit}>
                    {error && <div className="error-msg">{error}</div>}
                    <div className="form-group">
                        <label htmlFor="email">E-posta</label>
                        <input id="email" name="email" type="email" className="input" placeholder="ornek@email.com" required />
                    </div>
                    <div className="form-group">
                        <label htmlFor="password">Şifre</label>
                        <input id="password" name="password" type="password" className="input" placeholder="••••••••" required />
                    </div>
                    <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                        {loading ? "Giriş yapılıyor..." : "Giriş Yap"}
                    </button>
                </form>

                <p className="auth-divider">
                    Hesabınız yok mu? <Link href="/register">Üye olun</Link>
                </p>
            </div>
        </div>
    );
}
