"use client";

import { useState, useRef, useEffect } from "react";
import { useRouter } from "next/navigation";
import { Radio, X } from "lucide-react";

export function QuickLiveButton() {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [showModal, setShowModal] = useState(false);
    const [title, setTitle] = useState("");
    const inputRef = useRef<HTMLInputElement>(null);
    const router = useRouter();

    useEffect(() => {
        if (showModal) {
            setTimeout(() => inputRef.current?.focus(), 50);
        }
    }, [showModal]);

    const handleStart = async () => {
        setLoading(true);
        setError(null);
        try {
            const res = await fetch("/api/livekit/quick-start", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ title: title.trim() || undefined }),
            });
            const data = await res.json();
            if (res.ok && data.hostId) {
                setShowModal(false);
                router.push(`/live/${data.hostId}`);
            } else {
                setError(data.error || "Bir hata oluştu.");
            }
        } catch {
            setError("Sunucuya bağlanılamadı.");
        } finally {
            setLoading(false);
        }
    };

    return (
        <>
            <button
                onClick={() => setShowModal(true)}
                className="btn btn-primary btn-sm"
                title="Canlı Yayın Aç"
                style={{
                    background: "linear-gradient(135deg, #ef4444, #dc2626)",
                    boxShadow: "0 2px 8px rgba(239, 68, 68, 0.3)",
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                }}
            >
                <Radio size={16} />
                <span>Canlı Yayın Aç</span>
            </button>

            {showModal && (
                <div
                    style={{
                        position: "fixed",
                        inset: 0,
                        zIndex: 9999,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        background: "rgba(0,0,0,0.5)",
                    }}
                    onClick={(e) => { if (e.target === e.currentTarget) setShowModal(false); }}
                >
                    <div
                        style={{
                            background: "#fff",
                            borderRadius: "16px",
                            padding: "28px 24px 24px",
                            width: "min(420px, 92vw)",
                            boxShadow: "0 20px 60px rgba(0,0,0,0.25)",
                        }}
                    >
                        {/* Header */}
                        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "20px" }}>
                            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                                <span style={{ fontSize: "1.25rem" }}>🔴</span>
                                <span style={{ fontWeight: 800, fontSize: "1.1rem", color: "#1a1a1a" }}>
                                    Canlı Yayın Aç
                                </span>
                            </div>
                            <button
                                onClick={() => setShowModal(false)}
                                style={{ background: "none", border: "none", cursor: "pointer", color: "#666", padding: "4px" }}
                            >
                                <X size={20} />
                            </button>
                        </div>

                        {/* Input */}
                        <label style={{ display: "block", fontSize: "0.8rem", fontWeight: 600, color: "#555", marginBottom: "6px" }}>
                            Yayınınıza bir isim verin (Opsiyonel)
                        </label>
                        <input
                            ref={inputRef}
                            type="text"
                            value={title}
                            onChange={(e) => setTitle(e.target.value)}
                            onKeyDown={(e) => { if (e.key === "Enter" && !loading) handleStart(); }}
                            placeholder="Örn: Akşam İndirimleri"
                            maxLength={80}
                            style={{
                                width: "100%",
                                padding: "10px 14px",
                                borderRadius: "10px",
                                border: "1.5px solid #e2e8f0",
                                fontSize: "0.95rem",
                                outline: "none",
                                marginBottom: "20px",
                                boxSizing: "border-box",
                            }}
                        />

                        {/* Error */}
                        {error && (
                            <p style={{ color: "#ef4444", fontSize: "0.8rem", marginBottom: "12px" }}>{error}</p>
                        )}

                        {/* Actions */}
                        <div style={{ display: "flex", gap: "10px" }}>
                            <button
                                onClick={() => setShowModal(false)}
                                style={{
                                    flex: 1,
                                    padding: "10px",
                                    borderRadius: "10px",
                                    border: "1.5px solid #e2e8f0",
                                    background: "#fff",
                                    cursor: "pointer",
                                    fontWeight: 600,
                                    fontSize: "0.9rem",
                                    color: "#555",
                                }}
                            >
                                İptal
                            </button>
                            <button
                                onClick={handleStart}
                                disabled={loading}
                                style={{
                                    flex: 2,
                                    padding: "10px",
                                    borderRadius: "10px",
                                    border: "none",
                                    background: loading ? "#f87171" : "linear-gradient(135deg, #ef4444, #dc2626)",
                                    color: "#fff",
                                    fontWeight: 700,
                                    fontSize: "0.9rem",
                                    cursor: loading ? "not-allowed" : "pointer",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    gap: "8px",
                                }}
                            >
                                <Radio size={15} />
                                {loading ? "Başlatılıyor..." : "Yayını Başlat"}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </>
    );
}
