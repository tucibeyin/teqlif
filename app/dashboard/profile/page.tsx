"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useSession, signOut } from "next-auth/react";
import { ArrowLeft, X, Trash2 } from "lucide-react";
import Link from "next/link";

export default function ProfilePage() {
    const { data: session, update } = useSession();
    const router = useRouter();

    const [name, setName] = useState("");
    const [email, setEmail] = useState("");
    const [phone, setPhone] = useState("");
    const [currentPassword, setCurrentPassword] = useState("");
    const [password, setPassword] = useState("");
    const [passwordConfirm, setPasswordConfirm] = useState("");
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [message, setMessage] = useState({ text: "", type: "" });

    // Delete account states
    const [showDeleteModal, setShowDeleteModal] = useState(false);
    const [deleteConfirmText, setDeleteConfirmText] = useState("");
    const [deleting, setDeleting] = useState(false);

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
            const payload: any = { name, email, phone, password, passwordConfirm, currentPassword };
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

    const handleDeleteAccount = async () => {
        if (deleteConfirmText !== "SİL") return;
        setDeleting(true);
        try {
            const res = await fetch("/api/profile/delete", { method: "DELETE" });
            if (res.ok) {
                await signOut({ redirect: false });
                router.push("/");
            } else {
                setMessage({ text: "Hesap silinemedi. Lütfen tekrar deneyin.", type: "error" });
                setShowDeleteModal(false);
            }
        } catch {
            setMessage({ text: "Bir ağ hatası oluştu.", type: "error" });
            setShowDeleteModal(false);
        } finally {
            setDeleting(false);
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
                            <label className="form-label" htmlFor="currentPassword">Mevcut Şifre</label>
                            <input
                                id="currentPassword"
                                type="password"
                                className="form-input"
                                value={currentPassword}
                                onChange={(e) => setCurrentPassword(e.target.value)}
                                placeholder="Şifre değiştirmek için gereklidir"
                            />
                        </div>

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

                    {/* Danger Zone */}
                    <div style={{ marginTop: "2rem", paddingTop: "1.5rem", borderTop: "1px solid var(--border)" }}>
                        <p style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginBottom: "0.75rem" }}>
                            ⚠️ Bu işlem geri alınamaz. Hesabınız ve tüm verileriniz kalıcı olarak silinir.
                        </p>
                        <button
                            type="button"
                            onClick={() => { setShowDeleteModal(true); setDeleteConfirmText(""); }}
                            style={{
                                display: "flex",
                                alignItems: "center",
                                gap: "0.5rem",
                                padding: "0.6rem 1.2rem",
                                background: "transparent",
                                border: "1px solid #ef4444",
                                borderRadius: "var(--radius-md)",
                                color: "#ef4444",
                                fontWeight: 600,
                                fontSize: "0.875rem",
                                cursor: "pointer",
                            }}
                        >
                            <Trash2 size={16} />
                            Hesabımı Sil
                        </button>
                    </div>
                </div>
            </div>

            {/* Verification Modal */}
            {showVerificationModal && (
                <div style={{
                    position: "fixed",
                    top: 0, left: 0, right: 0, bottom: 0,
                    backgroundColor: "rgba(0,0,0,0.5)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    zIndex: 1000, padding: "1rem"
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
                                padding: "0.75rem", borderRadius: "var(--radius-md)", marginBottom: "1.5rem",
                                backgroundColor: message.type === "error" ? "rgba(239, 68, 68, 0.1)" : "rgba(34, 197, 94, 0.1)",
                                color: message.type === "error" ? "var(--error)" : "var(--success)",
                                fontWeight: 500, fontSize: "0.875rem", textAlign: "center"
                            }}>
                                {message.text}
                            </div>
                        )}

                        <form onSubmit={handleVerify}>
                            <div className="form-group" style={{ textAlign: "center" }}>
                                <input
                                    type="text" maxLength={6} className="form-input"
                                    style={{ textAlign: "center", fontSize: "1.5rem", letterSpacing: "8px", fontWeight: 700 }}
                                    value={verificationCode}
                                    onChange={(e) => setVerificationCode(e.target.value.replace(/\D/g, ""))}
                                    placeholder="000000" required autoFocus
                                />
                            </div>
                            <button type="submit" className="btn btn-primary"
                                style={{ width: "100%", marginTop: "1rem" }} disabled={verifying}>
                                {verifying ? "Doğrulanıyor..." : "Onayla ve Kaydet"}
                            </button>
                        </form>
                    </div>
                </div>
            )}

            {/* Delete Account Modal */}
            {showDeleteModal && (
                <div style={{
                    position: "fixed",
                    top: 0, left: 0, right: 0, bottom: 0,
                    backgroundColor: "rgba(0,0,0,0.6)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    zIndex: 1000, padding: "1rem"
                }}>
                    <div style={{
                        maxWidth: "420px", width: "100%", padding: "2rem",
                        background: "white", borderRadius: "var(--radius-lg)",
                        position: "relative", boxShadow: "0 20px 60px rgba(0,0,0,0.2)"
                    }}>
                        <button
                            onClick={() => setShowDeleteModal(false)}
                            style={{ position: "absolute", top: "1rem", right: "1rem", border: "none", background: "none", cursor: "pointer", color: "var(--text-secondary)" }}
                        >
                            <X size={20} />
                        </button>

                        <div style={{ textAlign: "center", marginBottom: "1.5rem" }}>
                            <div style={{ fontSize: "3rem", marginBottom: "0.5rem" }}>⚠️</div>
                            <h2 style={{ fontSize: "1.3rem", fontWeight: 700, color: "#ef4444", marginBottom: "0.5rem" }}>Hesabı Sil</h2>
                            <p style={{ fontSize: "0.875rem", color: "var(--text-secondary)", lineHeight: 1.6 }}>
                                Bu işlem <strong>geri alınamaz</strong>. Hesabınız, tüm ilanlarınız, teklifleriniz ve mesajlarınız kalıcı olarak silinecektir.
                            </p>
                        </div>

                        <div style={{ marginBottom: "1.5rem" }}>
                            <label style={{ display: "block", fontSize: "0.875rem", fontWeight: 600, marginBottom: "0.5rem", color: "#374151" }}>
                                Onaylamak için aşağıya <strong style={{ color: "#ef4444" }}>SİL</strong> yazın:
                            </label>
                            <input
                                type="text"
                                className="form-input"
                                value={deleteConfirmText}
                                onChange={(e) => setDeleteConfirmText(e.target.value)}
                                placeholder="SİL"
                                autoFocus
                            />
                        </div>

                        <button
                            onClick={handleDeleteAccount}
                            disabled={deleteConfirmText !== "SİL" || deleting}
                            style={{
                                width: "100%",
                                padding: "0.75rem",
                                background: deleteConfirmText === "SİL" ? "#ef4444" : "#fca5a5",
                                color: "white",
                                border: "none",
                                borderRadius: "var(--radius-md)",
                                fontWeight: 700,
                                fontSize: "0.95rem",
                                cursor: deleteConfirmText === "SİL" ? "pointer" : "not-allowed",
                                transition: "background 0.2s"
                            }}
                        >
                            {deleting ? "Siliniyor..." : "Hesabımı Kalıcı Olarak Sil"}
                        </button>
                    </div>
                </div>
            )}
        </div>
    );
}
