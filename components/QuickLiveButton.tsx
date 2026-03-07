"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Radio } from "lucide-react";

export function QuickLiveButton() {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const router = useRouter();

    const handleStart = async () => {
        setLoading(true);
        setError(null);
        try {
            const res = await fetch("/api/livekit/quick-start", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
            });
            const data = await res.json();
            if (res.ok && data.hostId) {
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
        <div>
            {error && (
                <p style={{ color: "var(--accent-red)", fontSize: "0.75rem", marginBottom: "0.5rem" }}>
                    {error}
                </p>
            )}
            <button
                onClick={handleStart}
                disabled={loading}
                className="btn btn-primary btn-sm"
                title="Canlı Yayın Aç"
                style={{
                    background: "linear-gradient(135deg, #ef4444, #dc2626)",
                    boxShadow: "0 2px 8px rgba(239, 68, 68, 0.3)",
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                    opacity: loading ? 0.7 : 1,
                }}
            >
                <Radio size={16} />
                <span>{loading ? "Başlatılıyor..." : "Canlı Yayın Aç"}</span>
            </button>
        </div>
    );
}
