"use client";

import { useState } from "react";
import { Mail, MessageSquare, AlertCircle, CheckCircle, HeadphonesIcon, HelpCircle, FileText } from "lucide-react";

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
        <div className="flex-1 w-full bg-gray-50/50">
            {/* Hero Section */}
            <div className="bg-white border-b border-[var(--border)] relative overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-b from-[var(--primary-50)] to-transparent opacity-60 pointer-events-none" />
                <div className="absolute top-0 right-0 w-[500px] h-[500px] bg-[var(--primary)] opacity-[0.03] blur-[100px] rounded-full pointer-events-none" />

                <div className="container py-16 relative z-10 text-center">
                    <div className="w-16 h-16 bg-[var(--primary-50)] text-[var(--primary)] rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-sm border border-[var(--primary-100)]">
                        <HeadphonesIcon size={32} />
                    </div>
                    <h1 className="text-4xl md:text-5xl font-extrabold text-gray-900 mb-4 tracking-tight">
                        Nasıl yardımcı <span className="text-[var(--primary)]">olabiliriz?</span>
                    </h1>
                    <p className="text-lg text-gray-500 max-w-2xl mx-auto">
                        Teqlif ekibi olarak size destek olmaktan mutluluk duyuyoruz. Soru, öneri ve şikayetlerinizi bize hızlıca iletebilirsiniz.
                    </p>
                </div>
            </div>

            {/* Main Content */}
            <div className="container py-12 -mt-8 relative z-20">
                <div className="max-w-6xl mx-auto flex flex-col lg:flex-row gap-8">

                    {/* Left Column: Info Cards */}
                    <div className="flex-1 space-y-6">
                        {/* Email Card */}
                        <div className="card hover:-translate-y-1 transition-transform duration-300 relative overflow-hidden group">
                            <div className="absolute top-0 left-0 w-1 h-full bg-gradient-to-b from-[var(--primary)] to-[var(--primary-dark)]" />
                            <div className="card-body p-8 sm:p-10 flex flex-col h-full justify-between">
                                <div>
                                    <div className="w-12 h-12 bg-[var(--primary-50)] text-[var(--primary)] rounded-xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
                                        <Mail size={24} />
                                    </div>
                                    <h3 className="text-xl font-bold text-gray-900 mb-2">Doğrudan E-Posta</h3>
                                    <p className="text-gray-500 mb-6">Genel sorularınız, ortaklık talepleri ve detaylı geri bildirimleriniz için bize yazın.</p>
                                </div>
                                <a href="mailto:destek@teqlif.com" className="inline-flex items-center gap-2 text-[var(--primary)] font-semibold hover:text-[var(--primary-dark)] transition-colors text-lg">
                                    destek@teqlif.com
                                </a>
                            </div>
                        </div>

                        {/* Moderation / Report Card */}
                        <div className="card hover:-translate-y-1 transition-transform duration-300 relative overflow-hidden group">
                            <div className="absolute top-0 left-0 w-1 h-full bg-gradient-to-b from-purple-500 to-indigo-600" />
                            <div className="card-body p-8 flex gap-5 items-start">
                                <div className="w-12 h-12 bg-purple-50 text-purple-600 rounded-xl flex items-center justify-center shrink-0 group-hover:scale-110 transition-transform">
                                    <AlertCircle size={24} />
                                </div>
                                <div>
                                    <h3 className="text-lg font-bold text-gray-900 mb-1">İçerik Şikayeti (UGC)</h3>
                                    <p className="text-sm text-gray-500 leading-relaxed">
                                        Kurallarımıza aykırı, sakıncalı veya güvenliği tehdit eden içerikleri anında bildirin. <strong className="font-semibold text-gray-800">Teqlif'te zorbalık ve yasadışı içeriğe sıfır tolerans gösterilir.</strong> Şikayetleriniz 24 saat içinde sonuçlandırılır.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Right Column: Form Area */}
                    <div className="flex-[1.4] lg:flex-[1.5]">
                        <div className="card shadow-[0_8px_30px_rgb(0,0,0,0.04)] border-[var(--border)] overflow-hidden">
                            <div className="p-8 sm:p-10">
                                <div className="flex items-center gap-3 mb-8">
                                    <div className="w-10 h-10 bg-gray-100 rounded-full flex items-center justify-center text-gray-600">
                                        <MessageSquare size={20} />
                                    </div>
                                    <div>
                                        <h2 className="text-2xl font-bold text-gray-900">İletişim Formu</h2>
                                        <p className="text-sm text-gray-500">Formu doldurun, size en kısa sürede dönüş yapalım.</p>
                                    </div>
                                </div>

                                {status === "success" ? (
                                    <div className="bg-[#F0FDF4] border border-[#BBF7D0] rounded-2xl p-10 text-center space-y-5 animate-in fade-in zoom-in duration-300">
                                        <div className="mx-auto w-20 h-20 bg-[#DCFCE7] rounded-full flex items-center justify-center text-[#16A34A] shadow-sm">
                                            <CheckCircle size={40} />
                                        </div>
                                        <div>
                                            <h3 className="text-2xl font-bold text-gray-900 mb-2">Talebiniz Alındı!</h3>
                                            <p className="text-gray-600 max-w-sm mx-auto">
                                                İletişime geçtiğiniz için teşekkürler. Ekibimiz konuyu inceleyip belirttiğiniz e-posta adresi üzerinden size dönüş sağlayacaktır.
                                            </p>
                                        </div>
                                        <button
                                            onClick={() => setStatus("idle")}
                                            className="btn btn-outline mt-4"
                                        >
                                            Yeni Bir Mesaj Gönder
                                        </button>
                                    </div>
                                ) : (
                                    <form onSubmit={handleSubmit} className="space-y-6">
                                        {status === "error" && (
                                            <div className="bg-[#FEF2F2] border border-[#FECACA] text-[#B91C1C] px-5 py-4 rounded-xl text-sm flex gap-3 items-start animate-in fade-in slide-in-from-top-2">
                                                <AlertCircle size={20} className="shrink-0 mt-0.5" />
                                                <p>Mesajınız gönderilirken teknik bir aksaklık oluştu. Lütfen daha sonra tekrar deneyin veya doğrudan <strong>destek@teqlif.com</strong> adresine e-posta gönderin.</p>
                                            </div>
                                        )}

                                        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                            <div className="form-group">
                                                <label>Adınız Soyadınız <span className="text-[var(--accent-red)]">*</span></label>
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
                                                <label>E-Posta Adresiniz <span className="text-[var(--accent-red)]">*</span></label>
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
                                            <label>Konu Seçimi <span className="text-[var(--accent-red)]">*</span></label>
                                            <select
                                                required
                                                value={formData.subject}
                                                onChange={(e) => setFormData({ ...formData, subject: e.target.value })}
                                                className="input font-medium"
                                                style={{ color: formData.subject ? "inherit" : "var(--text-muted)" }}
                                            >
                                                <option value="" disabled>Seçiniz...</option>
                                                <option value="general">Genel Soru / Bilgi Talebi</option>
                                                <option value="technical">Teknik Destek / Hata Bildirimi</option>
                                                <option value="report">Sakıncalı İçerik Şikayeti (UGC)</option>
                                                <option value="billing">Hesap & Ödeme İşlemleri</option>
                                                <option value="other">Diğer Konular</option>
                                            </select>
                                        </div>

                                        <div className="form-group">
                                            <label>Mesajınız <span className="text-[var(--accent-red)]">*</span></label>
                                            <textarea
                                                required
                                                rows={5}
                                                value={formData.message}
                                                onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                                                className="input p-4"
                                                placeholder="Lütfen talebinizi veya sorununuzu detaylı bir şekilde açıklayın..."
                                            ></textarea>
                                        </div>

                                        <div className="pt-2">
                                            <button
                                                type="submit"
                                                disabled={status === "loading"}
                                                className="btn btn-primary btn-lg w-full relative overflow-hidden group"
                                            >
                                                <span className={`flex items-center justify-center gap-2 transition-opacity ${status === "loading" ? "opacity-0" : "opacity-100"}`}>
                                                    Mesajı Gönder
                                                </span>
                                                {status === "loading" && (
                                                    <span className="absolute inset-0 flex items-center justify-center">
                                                        <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                                            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                                            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                                        </svg>
                                                        Gönderiliyor...
                                                    </span>
                                                )}
                                            </button>
                                        </div>
                                    </form>
                                )}
                            </div>

                            {/* Form Footer Note */}
                            <div className="bg-gray-50 border-t border-[var(--border)] p-6 sm:px-10 flex items-start gap-4 text-sm text-gray-500">
                                <HelpCircle size={20} className="shrink-0 text-gray-400 mt-0.5" />
                                <p>Destek ekibimiz genellikle <strong className="font-semibold text-gray-700">24 saat içinde</strong> dönüş yapmaktadır. Tatil günlerinde bu süre biraz uzayabilir.</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
