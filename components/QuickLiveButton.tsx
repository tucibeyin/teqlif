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
        <div style={{ position: "relative" }}>
            <button
                onClick={() => setIsOpen(!isOpen)}
                className="btn btn-primary btn-sm"
                title="Canlı Yayın Aç"
                style={{
                    background: "linear-gradient(135deg, #ef4444, #dc2626)", // Red for live
                    boxShadow: "0 2px 8px rgba(239, 68, 68, 0.3)",
                    display: "flex",
                    alignItems: "center",
                    gap: "8px"
                }}
            >
                <Radio size={16} />
                <span>Canlı Yayın Aç</span>
            </button>

            {isOpen && (
                <>
                    {/* Click-away backdrop */}
                    <div
                        onClick={() => setIsOpen(false)}
                        style={{
                            position: "fixed",
                            inset: 0,
                            zIndex: 998,
                            background: "transparent"
                        }}
                    />

                    <div style={{
                        position: "absolute",
                        top: "calc(100% + 12px)",
                        right: 0,
                        zIndex: 999,
                        width: "320px",
                        background: "var(--bg-card)",
                        border: "1px solid var(--border)",
                        borderRadius: "var(--radius-lg)",
                        padding: "1.5rem",
                        boxShadow: "var(--shadow-lg)",
                        animation: "fadeInUp 0.2s ease-out forwards",
                        pointerEvents: "auto"
                    }}>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
                            <h2 style={{ fontSize: "1rem", fontWeight: 700, margin: 0, color: "var(--text-primary)" }}>Hızlı Canlı Yayın</h2>
                            <button
                                onClick={() => setIsOpen(false)}
                                style={{ background: "transparent", border: "none", fontSize: "1.25rem", cursor: "pointer", color: "var(--text-muted)", padding: "4px" }}
                            >
                                &times;
                            </button>
                        </div>

                        {error && (
                            <div className="error-msg" style={{ marginBottom: "1rem", padding: "0.5rem 0.75rem" }}>
                                {error}
                            </div>
                        )}

                        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                            <div className="form-group">
                                <label>Yayın Başlığı</label>
                                <input
                                    type="text"
                                    value={title}
                                    onChange={(e) => setTitle(e.target.value)}
                                    placeholder="Yayın amacı..."
                                    className="input"
                                    required
                                    autoFocus
                                />
                            </div>

                            <div className="form-group">
                                <label>Başlangıç Fiyatı (₺)</label>
                                <input
                                    type="number"
                                    value={startingBid}
                                    onChange={(e) => setStartingBid(e.target.value)}
                                    placeholder="Varsayılan: 1₺"
                                    className="input"
                                    min="1"
                                />
                            </div>

                            <div className="form-group">
                                <label>Kapak Görseli</label>
                                <div style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
                                    <label style={{
                                        display: "inline-flex",
                                        alignItems: "center",
                                        justifyContent: "center",
                                        padding: "0.5rem",
                                        background: "var(--bg-input)",
                                        border: "1px dashed var(--border)",
                                        borderRadius: "var(--radius-md)",
                                        cursor: "pointer",
                                        color: "var(--text-secondary)",
                                        fontSize: "0.75rem",
                                        flex: 1,
                                        height: "42px"
                                    }}>
                                        {image ? "Değiştir" : "📁 Seç"}
                                        <input
                                            type="file"
                                            accept="image/*"
                                            onChange={handleImageChange}
                                            style={{ display: "none" }}
                                        />
                                    </label>

                                    {imagePreview && (
                                        <div style={{
                                            width: "42px",
                                            height: "42px",
                                            borderRadius: "var(--radius-sm)",
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
                                    background: "var(--accent-red)",
                                    boxShadow: "0 4px 12px rgba(239, 68, 68, 0.25)"
                                }}
                            >
                                {loading ? "..." : "YAYINI BAŞLAT"}
                            </button>
                        </form>
                    </div>
                </>
            )}
        </div>
    );
}
