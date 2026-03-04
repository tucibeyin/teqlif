"use client";

import { useState } from "react";
import { Mail, MessageSquare, AlertCircle, CheckCircle } from "lucide-react";

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
        <div className="flex-1 max-w-5xl mx-auto w-full px-4 py-12 flex flex-col md:flex-row gap-12 pt-24">
            {/* Contact Info Column */}
            <div className="flex-1 space-y-8">
                <div>
                    <h1 className="text-4xl font-extrabold text-gray-900 mb-4">Müşteri Destek</h1>
                    <p className="text-lg text-gray-600">
                        Size nasıl yardımcı olabiliriz? Sorularınız, önerileriniz veya karşılaştığınız sorunlar için bizimle iletişime geçin. Ekibimiz en kısa sürede size geri dönecektir.
                    </p>
                </div>

                <div className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 space-y-6">
                    <h2 className="text-xl font-bold border-b pb-4">Doğrudan İletişim</h2>

                    <div className="flex items-start gap-4">
                        <div className="bg-[var(--primary)] bg-opacity-10 p-3 rounded-full text-[var(--primary)] mt-1">
                            <Mail size={24} />
                        </div>
                        <div>
                            <h3 className="font-semibold text-gray-900">E-Posta Desteği</h3>
                            <p className="text-sm text-gray-500 mb-1">Genel sorularınız ve şikayetleriniz için:</p>
                            <a href="mailto:destek@teqlif.com" className="text-[var(--primary)] font-medium hover:underline">
                                destek@teqlif.com
                            </a>
                        </div>
                    </div>

                    <div className="flex items-start gap-4">
                        <div className="bg-purple-100 p-3 rounded-full text-purple-600 mt-1">
                            <AlertCircle size={24} />
                        </div>
                        <div>
                            <h3 className="font-semibold text-gray-900">İçerik Şikayeti (UGC)</h3>
                            <p className="text-sm text-gray-500">
                                Uygulama kurallarına aykırı, sakıncalı içerikleri (UGC) anında bize bildirin. Şikayetleriniz 24 saat içinde incelenip karara bağlanır.
                            </p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Contact Form Column */}
            <div className="flex-[1.5]">
                <div className="bg-white p-8 rounded-2xl shadow-lg border border-gray-100">
                    <h2 className="text-2xl font-bold mb-6 flex items-center gap-2">
                        <MessageSquare className="text-[var(--primary)]" />
                        Bize Ulaşın
                    </h2>

                    {status === "success" ? (
                        <div className="bg-green-50 border border-green-200 rounded-xl p-8 text-center space-y-4">
                            <div className="mx-auto w-16 h-16 bg-green-100 rounded-full flex items-center justify-center text-green-600 mb-2">
                                <CheckCircle size={32} />
                            </div>
                            <h3 className="text-xl font-bold text-green-800">Mesajınız Alındı!</h3>
                            <p className="text-green-700">
                                Bizimle iletişime geçtiğiniz için teşekkür ederiz. Destek ekibimiz en kısa sürede e-posta adresiniz üzerinden size dönüş yapacaktır.
                            </p>
                            <button
                                onClick={() => setStatus("idle")}
                                className="mt-4 text-green-700 font-semibold hover:underline"
                            >
                                Yeni bir mesaj gönder
                            </button>
                        </div>
                    ) : (
                        <form onSubmit={handleSubmit} className="space-y-5">
                            {status === "error" && (
                                <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-sm">
                                    Mesajınız gönderilirken bir hata oluştu. Lütfen daha sonra tekrar deneyin veya doğrudan e-posta gönderin.
                                </div>
                            )}
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
                                <div className="space-y-1">
                                    <label className="text-sm font-semibold text-gray-700">Adınız Soyadınız *</label>
                                    <input
                                        type="text"
                                        required
                                        value={formData.name}
                                        onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                                        className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent outline-none transition-all"
                                        placeholder="Ad Soyad"
                                    />
                                </div>
                                <div className="space-y-1">
                                    <label className="text-sm font-semibold text-gray-700">E-Posta Adresiniz *</label>
                                    <input
                                        type="email"
                                        required
                                        value={formData.email}
                                        onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                                        className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent outline-none transition-all"
                                        placeholder="adınız@ornek.com"
                                    />
                                </div>
                            </div>

                            <div className="space-y-1">
                                <label className="text-sm font-semibold text-gray-700">Konu *</label>
                                <select
                                    required
                                    value={formData.subject}
                                    onChange={(e) => setFormData({ ...formData, subject: e.target.value })}
                                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent outline-none transition-all bg-white"
                                >
                                    <option value="" disabled>Lütfen bir konu seçin</option>
                                    <option value="general">Genel Soru / Bilgi Talebi</option>
                                    <option value="technical">Teknik Destek</option>
                                    <option value="report">Sakıncalı İçerik Şikayeti (UGC)</option>
                                    <option value="billing">Ödeme ve Faturalandırma</option>
                                    <option value="other">Diğer</option>
                                </select>
                            </div>

                            <div className="space-y-1">
                                <label className="text-sm font-semibold text-gray-700">Mesajınız *</label>
                                <textarea
                                    required
                                    rows={5}
                                    value={formData.message}
                                    onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent outline-none transition-all resize-none"
                                    placeholder="Size nasıl yardımcı olabiliriz?"
                                ></textarea>
                            </div>

                            <button
                                type="submit"
                                disabled={status === "loading"}
                                className="w-full btn btn-primary py-4 text-lg rounded-xl flex items-center justify-center disabled:opacity-70 disabled:cursor-not-allowed"
                            >
                                {status === "loading" ? "Gönderiliyor..." : "Mesajı Gönder"}
                            </button>
                        </form>
                    )}
                </div>
            </div>
        </div>
    );
}
