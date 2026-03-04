"use client";

import { useState } from "react";
import { Mail, MessageSquare, AlertCircle, CheckCircle, HeadphonesIcon, HelpCircle } from "lucide-react";

export default function SupportContent() {
    const [formData, setFormData] = useState({
        name: "",
        email: "",
        subject: "",
        message: "",
    });
    const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setStatus("loading");

        try {
            const res = await fetch("/api/support", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(formData),
            });

            if (!res.ok) {
                throw new Error("Sunucu hatası");
            }

            setStatus("success");
            setFormData({ name: "", email: "", subject: "", message: "" });
        } catch (error) {
            console.error("Form gönderim hatası:", error);
            setStatus("error");
        }
    };

    return (
        <div className="flex-1 w-full pb-16">
            <section className="hero">
                <div className="container">
                    <div style={{ padding: "1rem", display: "inline-flex", background: "var(--bg-card)", borderRadius: "var(--radius-xl)", boxShadow: "var(--shadow-sm)", marginBottom: "1.5rem" }}>
                        <HeadphonesIcon size={48} className="text-cyan-500" />
                    </div>
                    <h1 className="hero-title">
                        Kullanıcı <span style={{ color: "var(--primary)" }}>Destek Merkezi</span>
                    </h1>
                    <p className="hero-subtitle">
                        teqlif ekibi olarak size destek olmaktan mutluluk duyuyoruz. Soru, öneri ve şikayetlerinizi bize hızlıca iletebilirsiniz. Ekibimiz sizinle en kısa sürede iletişime geçecektir.
                    </p>
                </div>
            </section>

            <div className="container" style={{ marginTop: "-2rem", position: "relative", zIndex: 10 }}>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))", gap: "2rem" }}>

                    {/* Left Column: Direct Info */}
                    <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
                        <div className="card">
                            <div className="card-body">
                                <div style={{ display: "flex", alignItems: "center", gap: "1rem", marginBottom: "1rem" }}>
                                    <div style={{ width: "48px", height: "48px", background: "var(--primary-50)", color: "var(--primary)", borderRadius: "var(--radius-md)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                                        <Mail size={24} />
                                    </div>
                                    <h2 style={{ fontSize: "1.25rem", fontWeight: 700, margin: 0 }}>Doğrudan İletişim</h2>
                                </div>
                                <p style={{ color: "var(--text-secondary)", marginBottom: "1rem", fontSize: "0.95rem" }}>
                                    Genel sorularınız, ortaklık talepleri ve detaylı görüşmeler için bize direkt olarak e-posta gönderebilirsiniz.
                                </p>
                                <a href="mailto:destek@teqlif.com" style={{ fontSize: "1.125rem", fontWeight: 600, color: "var(--primary)", display: "inline-flex", alignItems: "center", gap: "0.5rem" }}>
                                    ✉️ destek@teqlif.com
                                </a>
                            </div>
                        </div>

                        <div className="card" style={{ borderColor: "rgba(239, 68, 68, 0.3)" }}>
                            <div className="card-body">
                                <div style={{ display: "flex", alignItems: "center", gap: "1rem", marginBottom: "1rem" }}>
                                    <div style={{ width: "48px", height: "48px", background: "rgba(239, 68, 68, 0.1)", color: "#ef4444", borderRadius: "var(--radius-md)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                                        <AlertCircle size={24} />
                                    </div>
                                    <h2 style={{ fontSize: "1.25rem", fontWeight: 700, margin: 0 }}>İçerik Şikayeti (UGC)</h2>
                                </div>
                                <p style={{ color: "var(--text-secondary)", fontSize: "0.95rem", lineHeight: 1.6 }}>
                                    Kurallarımıza aykırı, sakıncalı veya güvenliği tehdit eden içerikleri anında bildirin.
                                    <strong style={{ color: "var(--text-primary)" }}> teqlif'te zorbalık ve yasadışı içeriğe sıfır tolerans gösterilir.</strong> Şikayetleriniz 24 saat içinde sonuçlandırılır.
                                </p>
                            </div>
                        </div>
                    </div>

                    {/* Right Column: Support Form */}
                    <div className="card">
                        <div className="card-body" style={{ padding: "2rem" }}>
                            <div style={{ display: "flex", alignItems: "center", gap: "0.75rem", marginBottom: "2rem" }}>
                                <MessageSquare size={24} style={{ color: "var(--primary)" }} />
                                <h2 style={{ fontSize: "1.5rem", fontWeight: 800, margin: 0 }}>Bize Yazın</h2>
                            </div>

                            {status === "success" ? (
                                <div style={{ textAlign: "center", padding: "3rem 1rem" }}>
                                    <div style={{ display: "inline-flex", background: "#dcfce7", color: "#16a34a", padding: "1rem", borderRadius: "50%", marginBottom: "1rem" }}>
                                        <CheckCircle size={48} />
                                    </div>
                                    <h3 style={{ fontSize: "1.5rem", fontWeight: 700, marginBottom: "1rem" }}>Talebiniz Alındı!</h3>
                                    <p style={{ color: "var(--text-secondary)", marginBottom: "2rem", maxWidth: "400px", margin: "0 auto 2rem" }}>
                                        İletişime geçtiğiniz için teşekkürler. Ekibimiz konuyu inceleyip belirttiğiniz e-posta adresi üzerinden size dönüş sağlayacaktır.
                                    </p>
                                    <button onClick={() => setStatus("idle")} className="btn btn-outline" style={{ padding: "0.75rem 2rem" }}>
                                        Yeni Bir Mesaj Gönder
                                    </button>
                                </div>
                            ) : (
                                <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
                                    {status === "error" && (
                                        <div style={{ background: "#fef2f2", border: "1px solid #fecaca", color: "#b91c1c", padding: "1rem", borderRadius: "var(--radius-md)", fontSize: "0.9rem", display: "flex", gap: "0.75rem", alignItems: "flex-start" }}>
                                            <AlertCircle size={20} style={{ flexShrink: 0 }} />
                                            <span>Mesajınız gönderilirken teknik bir aksaklık oluştu. Lütfen daha sonra tekrar deneyin veya doğrudan <strong>destek@teqlif.com</strong> adresine e-posta gönderin.</span>
                                        </div>
                                    )}

                                    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1.5rem" }}>
                                        <div className="form-group">
                                            <label>Adınız Soyadınız *</label>
                                            <input
                                                type="text"
                                                required
                                                value={formData.name}
                                                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                                                className="input"
                                                placeholder="Örn: Ahmet Yılmaz"
                                            />
                                        </div>
                                        <div className="form-group">
                                            <label>E-Posta Adresiniz *</label>
                                            <input
                                                type="email"
                                                required
                                                value={formData.email}
                                                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                                                className="input"
                                                placeholder="ornek@email.com"
                                            />
                                        </div>
                                    </div>

                                    <div className="form-group">
                                        <label>Konu Seçimi *</label>
                                        <select
                                            required
                                            value={formData.subject}
                                            onChange={(e) => setFormData({ ...formData, subject: e.target.value })}
                                            className="input"
                                            style={{ cursor: "pointer" }}
                                        >
                                            <option value="" disabled>Lütfen bir konu seçin</option>
                                            <option value="general">Genel Soru / Bilgi Talebi</option>
                                            <option value="technical">Teknik Destek / Hata Bildirimi</option>
                                            <option value="report">Sakıncalı İçerik Şikayeti (UGC)</option>
                                            <option value="billing">Hesap & Ödeme İşlemleri</option>
                                            <option value="other">Diğer Konular</option>
                                        </select>
                                    </div>

                                    <div className="form-group">
                                        <label>Mesajınız *</label>
                                        <textarea
                                            required
                                            rows={6}
                                            value={formData.message}
                                            onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                                            className="input"
                                            placeholder="Detaylı olarak sorununuzu veya talebinizi iletebilirsiniz..."
                                        ></textarea>
                                    </div>

                                    <button
                                        type="submit"
                                        disabled={status === "loading"}
                                        className="btn btn-primary btn-full"
                                        style={{ padding: "1rem", fontSize: "1.125rem", marginTop: "1rem" }}
                                    >
                                        {status === "loading" ? "Gönderiliyor..." : "Mesajı Gönder"}
                                    </button>
                                </form>
                            )}
                        </div>
                        <div className="card-footer" style={{ display: "flex", alignItems: "center", gap: "0.75rem", fontSize: "0.85rem", color: "var(--text-muted)" }}>
                            <HelpCircle size={18} />
                            <span>Destek ekibimiz genellikle <strong>24 saat içinde</strong> dönüş yapmaktadır.</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
