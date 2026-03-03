"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Radio } from "lucide-react";

export function QuickLiveButton() {
    const [isOpen, setIsOpen] = useState(false);
    const [title, setTitle] = useState("");
    const [startingBid, setStartingBid] = useState("");
    const [image, setImage] = useState<File | null>(null);
    const [imagePreview, setImagePreview] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const router = useRouter();
    const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        if (e.target.files && e.target.files[0]) {
            const file = e.target.files[0];
            setImage(file);
            setImagePreview(URL.createObjectURL(file));
        }
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(null);

        if (!title.trim()) {
            setError("Yayın başlığı zorunludur.");
            setLoading(false);
            return;
        }

        try {
            let uploadedImageUrl = null;
            if (image) {
                const formData = new FormData();
                formData.append("file", image);
                const uploadRes = await fetch("/api/upload", {
                    method: "POST",
                    body: formData,
                });

                if (uploadRes.ok) {
                    const uploadData = await uploadRes.json();
                    uploadedImageUrl = uploadData.url;
                } else {
                    throw new Error("Resim yüklenemedi.");
                }
            }

            const res = await fetch("/api/livekit/quick-start", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    title,
                    startingBid: Number(startingBid) || 1,
                    images: uploadedImageUrl ? [uploadedImageUrl] : []
                })
            });
            const data = await res.json();

            if (res.ok && data.id) {
                setIsOpen(false);
                router.push(`/ad/${data.id}`);
            } else {
                setError(data.error || "Bir hata oluştu.");
            }
        } catch (err) {
            setError("Sunucuya bağlanılamadı.");
        } finally {
            setLoading(false);
        }
    };

    return (
        <>
            <button
                onClick={() => setIsOpen(true)}
                className="btn btn-primary btn-sm"
                title="Canlı Yayın Aç"
                style={{
                    background: "linear-gradient(135deg, #ef4444, #dc2626)", // Red for live
                    boxShadow: "0 2px 8px rgba(239, 68, 68, 0.3)"
                }}
            >
                <Radio size={18} />
                <span>Canlı Yayın Aç</span>
            </button>

            {isOpen && (
                <div style={{
                    position: "fixed",
                    inset: 0,
                    zIndex: 9999,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    background: "rgba(0,0,0,0.5)",
                    backdropFilter: "blur(5px)",
                }}>
                    <div style={{
                        background: "var(--bg-card)",
                        border: "1px solid var(--border)",
                        borderRadius: "1rem",
                        padding: "2rem",
                        width: "100%",
                        maxWidth: "400px",
                        boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.25)"
                    }}>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.5rem" }}>
                            <h2 style={{ fontSize: "1.25rem", fontWeight: 700, margin: 0 }}>Hızlı Canlı Yayın Aç</h2>
                            <button
                                onClick={() => setIsOpen(false)}
                                style={{ background: "transparent", border: "none", fontSize: "1.5rem", cursor: "pointer", color: "var(--text-muted)" }}
                            >
                                &times;
                            </button>
                        </div>

                        {error && (
                            <div style={{ background: "rgba(239, 68, 68, 0.1)", color: "var(--danger)", padding: "0.75rem", borderRadius: "0.5rem", marginBottom: "1rem", fontSize: "0.875rem" }}>
                                {error}
                            </div>
                        )}

                        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                            <div>
                                <label style={{ display: "block", fontSize: "0.875rem", fontWeight: 500, marginBottom: "0.5rem", color: "var(--text-secondary)" }}>
                                    Yayın Başlığı <span style={{ color: "var(--danger)" }}>*</span>
                                </label>
                                <input
                                    type="text"
                                    value={title}
                                    onChange={(e) => setTitle(e.target.value)}
                                    placeholder="Örn: Antika Saat Açık Arttırması"
                                    className="input-field"
                                    required
                                />
                            </div>

                            <div>
                                <label style={{ display: "block", fontSize: "0.875rem", fontWeight: 500, marginBottom: "0.5rem", color: "var(--text-secondary)" }}>
                                    Başlangıç Fiyatı (₺)
                                </label>
                                <input
                                    type="number"
                                    value={startingBid}
                                    onChange={(e) => setStartingBid(e.target.value)}
                                    placeholder="Opsiyonel (Varsayılan: 1₺)"
                                    className="input-field"
                                    min="1"
                                />
                            </div>

                            <div>
                                <label style={{ display: "block", fontSize: "0.875rem", fontWeight: 500, marginBottom: "0.5rem", color: "var(--text-secondary)" }}>
                                    Kapak Fotoğrafı (İsteğe Bağlı)
                                </label>
                                <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                    <label style={{
                                        display: "inline-block",
                                        padding: "0.5rem 1rem",
                                        background: "var(--bg-secondary)",
                                        border: "1px dashed var(--border)",
                                        borderRadius: "0.5rem",
                                        cursor: "pointer",
                                        color: "var(--text-secondary)",
                                        fontSize: "0.875rem",
                                        textAlign: "center",
                                        flex: 1
                                    }}>
                                        {image ? "Değiştir" : "📁 Fotoğraf Seç"}
                                        <input
                                            type="file"
                                            accept="image/*"
                                            onChange={handleImageChange}
                                            style={{ display: "none" }}
                                        />
                                    </label>

                                    {imagePreview && (
                                        <div style={{
                                            width: "60px",
                                            height: "60px",
                                            borderRadius: "0.5rem",
                                            overflow: "hidden",
                                            border: "1px solid var(--border)",
                                            flexShrink: 0
                                        }}>
                                            <img src={imagePreview} alt="Preview" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                                        </div>
                                    )}
                                </div>
                            </div>

                            <button
                                type="submit"
                                disabled={loading}
                                className="btn btn-primary btn-full"
                                style={{
                                    marginTop: "0.5rem",
                                    padding: "0.875rem",
                                    fontSize: "1rem",
                                    background: "var(--danger)",
                                    border: "none"
                                }}
                            >
                                {loading ? "Hazırlanıyor..." : "🔴 Yayını Hemen Başlat"}
                            </button>
                        </form>
                    </div>
                </div>
            )}
        </>
    );
}

