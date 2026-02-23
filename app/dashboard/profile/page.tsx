"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useSession } from "next-auth/react";
import { ArrowLeft } from "lucide-react";
import Link from "next/link";

export default function ProfilePage() {
    const { data: session, update } = useSession();
    const router = useRouter();

    const [name, setName] = useState("");
    const [email, setEmail] = useState("");
    const [phone, setPhone] = useState("");
    const [password, setPassword] = useState("");
    const [passwordConfirm, setPasswordConfirm] = useState("");
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [message, setMessage] = useState({ text: "", type: "" });

    useEffect(() => {
        const fetchProfile = async () => {
            try {
                const res = await fetch("/api/profile");
                if (res.ok) {
                    const data = await res.json();
                    setName(data.name || "");
                    setEmail(data.email || "");
                    setPhone(data.phone || "");
                }
            } catch (error) {
                console.error("Profil yüklenemedi", error);
            } finally {
                setLoading(false);
            }
        };
        fetchProfile();
    }, []);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setSaving(true);
        setMessage({ text: "", type: "" });

        try {
            const res = await fetch("/api/profile", {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ name, email, phone, password, passwordConfirm })
            });

            const data = await res.json();

            if (res.ok) {
                // Instantly update the NextAuth JWT to reflect the new Name/Email without requiring re-login
                await update({ name: data.user.name, email: data.user.email });
                setMessage({ text: data.message, type: "success" });
            } else {
                setMessage({ text: data.message || "Güncelleme başarısız", type: "error" });
            }
        } catch (error) {
            setMessage({ text: "Bir ağ hatası oluştu", type: "error" });
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="container" style={{ padding: "4rem 0", display: "flex", justifyContent: "center" }}>
                <div className="loading-spinner"></div>
            </div>
        );
    }

    return (
        <div className="dashboard">
            <div className="container">
                <div style={{ marginBottom: "2rem" }}>
                    <Link href="/dashboard" style={{ display: "inline-flex", alignItems: "center", gap: "0.5rem", color: "var(--text-secondary)", textDecoration: "none" }}>
                        <ArrowLeft size={16} />
                        <span>Panele Dön</span>
                    </Link>
                </div>

                <div className="auth-card" style={{ maxWidth: "600px", margin: "0 auto", padding: "2rem", background: "white", borderRadius: "var(--radius-lg)", boxShadow: "0 4px 6px -1px rgba(0,0,0,0.1)" }}>
                    <div className="auth-header">
                        <h1 className="auth-title">Profilimi Düzenle</h1>
                        <p className="auth-subtitle">Kişisel bilgilerinizi buradan güncelleyebilirsiniz.</p>
                    </div>

                    {message.text && (
                        <div style={{
                            padding: "1rem",
                            borderRadius: "var(--radius-md)",
                            marginBottom: "1.5rem",
                            backgroundColor: message.type === "error" ? "rgba(239, 68, 68, 0.1)" : "rgba(34, 197, 94, 0.1)",
                            color: message.type === "error" ? "var(--error)" : "var(--success)",
                            fontWeight: 500,
                            textAlign: "center"
                        }}>
                            {message.text}
                        </div>
                    )}

                    <form className="auth-form" onSubmit={handleSubmit}>
                        <div className="form-group">
                            <label className="form-label" htmlFor="name">Ad Soyad</label>
                            <input
                                id="name"
                                type="text"
                                className="form-input"
                                value={name}
                                onChange={(e) => setName(e.target.value)}
                                required
                            />
                        </div>

                        <div className="form-group">
                            <label className="form-label" htmlFor="email">E-Posta Adresi</label>
                            <input
                                id="email"
                                type="email"
                                className="form-input"
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                                required
                            />
                        </div>

                        <div className="form-group">
                            <label className="form-label" htmlFor="phone">Telefon Numarası</label>
                            <input
                                id="phone"
                                type="tel"
                                className="form-input"
                                value={phone}
                                onChange={(e) => setPhone(e.target.value)}
                                placeholder="05XX XXX XX XX"
                            />
                        </div>

                        <hr style={{ margin: "2rem 0", border: "none", borderTop: "1px solid var(--border)" }} />

                        <div className="form-group">
                            <label className="form-label" htmlFor="password">Yeni Şifre</label>
                            <input
                                id="password"
                                type="password"
                                className="form-input"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                placeholder="Değiştirmek istemiyorsanız boş bırakın"
                                minLength={6}
                            />
                        </div>

                        <div className="form-group">
                            <label className="form-label" htmlFor="passwordConfirm">Yeni Şifre (Tekrar)</label>
                            <input
                                id="passwordConfirm"
                                type="password"
                                className="form-input"
                                value={passwordConfirm}
                                onChange={(e) => setPasswordConfirm(e.target.value)}
                                placeholder="Yeni şifrenizi tekrar girin"
                                minLength={6}
                            />
                        </div>

                        <button
                            type="submit"
                            className="btn btn-primary"
                            style={{ width: "100%", marginTop: "1rem" }}
                            disabled={saving}
                        >
                            {saving ? "Kaydediliyor..." : "Değişiklikleri Kaydet"}
                        </button>
                    </form>
                </div>
            </div>
        </div>
    );
}
