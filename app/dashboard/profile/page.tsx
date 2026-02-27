"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useSession } from "next-auth/react";
import { ArrowLeft, X } from "lucide-react";
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

    // 2FA Verification States
    const [showVerificationModal, setShowVerificationModal] = useState(false);
    const [verificationCode, setVerificationCode] = useState("");
    const [verifying, setVerifying] = useState(false);

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

    const handleSubmit = async (e?: React.FormEvent, code?: string) => {
        if (e) e.preventDefault();

        if (code) {
            setVerifying(true);
        } else {
            setSaving(true);
        }

        setMessage({ text: "", type: "" });

        try {
            const payload: any = { name, email, phone, password, passwordConfirm };
            if (code) {
                payload.verificationCode = code;
            }

            const res = await fetch("/api/profile", {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload)
            });

            const data = await res.json();

            if (res.status === 202 && data.requiresVerification) {
                // Code sent, show modal
                setShowVerificationModal(true);
                setMessage({ text: data.message, type: "info" });
            } else if (res.ok) {
                // Instantly update the NextAuth JWT to reflect the new Name/Email without requiring re-login
                await update({ name: data.user.name, email: data.user.email });
                setMessage({ text: data.message, type: "success" });
                setShowVerificationModal(false);
                setVerificationCode("");
                setPassword("");
                setPasswordConfirm("");
            } else {
                setMessage({ text: data.message || "Güncelleme başarısız", type: "error" });
            }
        } catch (error) {
            setMessage({ text: "Bir ağ hatası oluştu", type: "error" });
        } finally {
            setSaving(false);
            setVerifying(false);
        }
    };

    const handleVerify = (e: React.FormEvent) => {
        e.preventDefault();
        if (verificationCode.length !== 6) {
            setMessage({ text: "Lütfen 6 haneli kodu girin", type: "error" });
            return;
        }
        handleSubmit(undefined, verificationCode);
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

                    {message.text && !showVerificationModal && (
                        <div style={{
                            padding: "1rem",
                            borderRadius: "var(--radius-md)",
                            marginBottom: "1.5rem",
                            backgroundColor: message.type === "error" ? "rgba(239, 68, 68, 0.1)" : message.type === "info" ? "rgba(59, 130, 246, 0.1)" : "rgba(34, 197, 94, 0.1)",
                            color: message.type === "error" ? "var(--error)" : message.type === "info" ? "#3b82f6" : "var(--success)",
                            fontWeight: 500,
                            textAlign: "center"
                        }}>
                            {message.text}
                        </div>
                    )}

                    <form className="auth-form" onSubmit={(e) => handleSubmit(e)}>
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
                            {saving ? "Kod Gönderiliyor..." : "Değişiklikleri Kaydet"}
                        </button>
                    </form>
                </div>
            </div>

            {/* Verification Modal */}
            {showVerificationModal && (
                <div style={{
                    position: "fixed",
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    backgroundColor: "rgba(0,0,0,0.5)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    zIndex: 1000,
                    padding: "1rem"
                }}>
                    <div className="auth-card" style={{ maxWidth: "400px", width: "100%", padding: "2rem", background: "white", borderRadius: "var(--radius-lg)", position: "relative" }}>
                        <button
                            onClick={() => setShowVerificationModal(false)}
                            style={{ position: "absolute", top: "1rem", right: "1rem", border: "none", background: "none", cursor: "pointer", color: "var(--text-secondary)" }}
                        >
                            <X size={20} />
                        </button>

                        <div className="auth-header" style={{ textAlign: "center", marginBottom: "1.5rem" }}>
                            <h2 style={{ fontSize: "1.5rem", fontWeight: 700, marginBottom: "0.5rem" }}>Doğrulama Gerekli</h2>
                            <p className="auth-subtitle" style={{ fontSize: "0.875rem" }}>Lütfen e-postanıza gönderilen 6 haneli kodu girin.</p>
                        </div>

                        {message.text && (
                            <div style={{
                                padding: "0.75rem",
                                borderRadius: "var(--radius-md)",
                                marginBottom: "1.5rem",
                                backgroundColor: message.type === "error" ? "rgba(239, 68, 68, 0.1)" : "rgba(34, 197, 94, 0.1)",
                                color: message.type === "error" ? "var(--error)" : "var(--success)",
                                fontWeight: 500,
                                fontSize: "0.875rem",
                                textAlign: "center"
                            }}>
                                {message.text}
                            </div>
                        )}

                        <form onSubmit={handleVerify}>
                            <div className="form-group" style={{ textAlign: "center" }}>
                                <input
                                    type="text"
                                    maxLength={6}
                                    className="form-input"
                                    style={{ textAlign: "center", fontSize: "1.5rem", letterSpacing: "8px", fontWeight: 700 }}
                                    value={verificationCode}
                                    onChange={(e) => setVerificationCode(e.target.value.replace(/\D/g, ""))}
                                    placeholder="000000"
                                    required
                                    autoFocus
                                />
                            </div>
                            <button
                                type="submit"
                                className="btn btn-primary"
                                style={{ width: "100%", marginTop: "1rem" }}
                                disabled={verifying}
                            >
                                {verifying ? "Doğrulanıyor..." : "Onayla ve Kaydet"}
                            </button>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
}
