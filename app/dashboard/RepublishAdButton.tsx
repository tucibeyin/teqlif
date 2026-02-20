"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw } from "lucide-react";

export default function RepublishAdButton({ id }: { id: string }) {
    const [isLoading, setIsLoading] = useState(false);
    const router = useRouter();

    const handleRepublish = async () => {
        if (!confirm("İlanı 30 gün daha yayınlamak istiyor musunuz?")) return;

        setIsLoading(true);
        try {
            const res = await fetch(`/api/ads/${id}/republish`, { method: "PATCH" });
            if (res.ok) {
                router.refresh();
            } else {
                const data = await res.json();
                alert(data.message || "Bir hata oluştu.");
            }
        } catch (error) {
            console.error(error);
            alert("Sunucuya ulaşılamadı.");
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <button
            onClick={handleRepublish}
            disabled={isLoading}
            className="btn btn-outline"
            style={{
                padding: "0.25rem 0.5rem",
                borderRadius: "var(--radius-sm)",
                fontSize: "0.875rem",
                fontWeight: 600,
                color: "var(--primary)",
                borderColor: "var(--primary)",
                background: "rgba(0, 188, 212, 0.1)",
                display: "flex",
                alignItems: "center",
                gap: "4px"
            }}
        >
            <RefreshCw size={14} />
            {isLoading ? "..." : "Yeniden Yayınla"}
        </button>
    );
}
