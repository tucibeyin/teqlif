"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function DeleteAdButton({ id }: { id: string }) {
    const router = useRouter();
    const [loading, setLoading] = useState(false);

    async function handleDelete() {
        if (!confirm("Bu ilanı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.")) return;

        setLoading(true);
        try {
            const res = await fetch(`/api/ads/${id}`, { method: "DELETE" });
            if (res.ok) {
                router.refresh();
            } else {
                alert("Silme işlemi başarısız.");
                setLoading(false);
            }
        } catch (err) {
            alert("Bir hata oluştu.");
            setLoading(false);
        }
    }

    return (
        <button
            onClick={handleDelete}
            disabled={loading}
            style={{
                background: "transparent",
                border: "none",
                color: "var(--accent-red)",
                cursor: loading ? "wait" : "pointer",
                padding: "0.25rem 0.5rem",
                borderRadius: "var(--radius-sm)",
                fontSize: "0.875rem",
                fontWeight: 600,
                transition: "background 0.2s"
            }}
            onMouseOver={(e) => e.currentTarget.style.background = "rgba(220, 53, 69, 0.1)"}
            onMouseOut={(e) => e.currentTarget.style.background = "transparent"}
        >
            {loading ? "Siliniyor..." : "Sil"}
        </button>
    );
}
