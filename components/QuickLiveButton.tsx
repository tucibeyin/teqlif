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
        } else {
            setTitle("");
            setError(null);
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
            {/* Trigger button */}
            <button
                onClick={() => setShowModal(true)}
                className="btn btn-primary btn-sm"
                title="Canlı Yayın Aç"
                style={{
                    background: "linear-gradient(135deg, #ef4444, #dc2626)",
                    boxShadow: "0 2px 8px rgba(239,68,68,0.3)",
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                }}
            >
                <Radio size={16} />
                <span>Canlı Yayın Aç</span>
            </button>

            {/* Modal */}
            {showModal && (
                <div
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
                    onClick={(e) => { if (e.target === e.currentTarget) setShowModal(false); }}
                >
                    <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm mx-4 p-6">
                        {/* Header */}
                        <div className="flex items-center justify-between mb-5">
                            <div className="flex items-center gap-2">
                                <span className="text-xl">🔴</span>
                                <span className="font-extrabold text-lg text-gray-900">Canlı Yayın Aç</span>
                            </div>
                            <button
                                onClick={() => setShowModal(false)}
                                className="text-gray-400 hover:text-gray-600 p-1 rounded-lg hover:bg-gray-100 transition-colors"
                            >
                                <X size={20} />
                            </button>
                        </div>

                        {/* Title input */}
                        <label className="block text-sm font-semibold text-gray-500 mb-1.5">
                            Yayınınıza bir isim verin{" "}
                            <span className="font-normal text-gray-400">(Opsiyonel)</span>
                        </label>
                        <input
                            ref={inputRef}
                            type="text"
                            value={title}
                            onChange={(e) => setTitle(e.target.value)}
                            onKeyDown={(e) => { if (e.key === "Enter" && !loading) handleStart(); }}
                            placeholder="Örn: Akşam İndirimleri"
                            maxLength={80}
                            className="w-full px-3.5 py-2.5 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-red-300 focus:border-transparent mb-5"
                        />

                        {/* Error */}
                        {error && (
                            <p className="text-red-500 text-xs mb-3">{error}</p>
                        )}

                        {/* Actions */}
                        <div className="flex gap-2.5">
                            <button
                                onClick={() => setShowModal(false)}
                                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-500 hover:bg-gray-50 transition-colors"
                            >
                                İptal
                            </button>
                            <button
                                onClick={handleStart}
                                disabled={loading}
                                className="flex-[2] py-2.5 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2 disabled:opacity-70 transition-opacity"
                                style={{ background: "linear-gradient(135deg, #ef4444, #dc2626)" }}
                            >
                                <Radio size={14} />
                                {loading ? "Başlatılıyor..." : "Yayını Başlat"}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </>
    );
}
