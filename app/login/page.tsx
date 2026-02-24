"use client";
import { useState, Suspense } from "react";
import Link from "next/link";
import { signIn } from "next-auth/react";
import { useRouter, useSearchParams } from "next/navigation";

function LoginForm() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const callbackUrl = searchParams.get("callbackUrl") || "/";
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
            router.push(callbackUrl);
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
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
                            <label htmlFor="password" style={{ marginBottom: 0 }}>Şifre</label>
                            <Link href="/forgot-password" style={{ fontSize: "0.85rem", color: "var(--primary)", textDecoration: "none", fontWeight: 500 }}>
                                Şifremi unuttum
                            </Link>
                        </div>
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

export default function LoginPage() {
    return (
        <Suspense>
            <LoginForm />
        </Suspense>
    );
}
