"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function FavoriteButton({
    adId,
    initialIsFavorite,
    isLoggedIn,
}: {
    adId: string;
    initialIsFavorite: boolean;
    isLoggedIn: boolean;
}) {
    const [isFavorite, setIsFavorite] = useState(initialIsFavorite);
    const [loading, setLoading] = useState(false);
    const router = useRouter();

    const handleToggle = async () => {
        if (!isLoggedIn) {
            router.push("/login");
            return;
        }

        setLoading(true);
        try {
            if (isFavorite) {
                // Remove
                const res = await fetch(`/api/favorites/${adId}`, {
                    method: "DELETE",
                });
                if (res.ok) setIsFavorite(false);
            } else {
                // Add
                const res = await fetch("/api/favorites", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ adId }),
                });
                if (res.ok) setIsFavorite(true);
            }
            router.refresh();
        } catch (error) {
            console.error("Failed to toggle favorite", error);
        } finally {
            setLoading(false);
        }
    };

    return (
        <button
            onClick={handleToggle}
            disabled={loading}
            style={{
                background: "none",
                border: "none",
                cursor: "pointer",
                padding: "0.25rem",
                display: "inline-flex",
                alignItems: "center",
                justifyContent: "center",
                color: isFavorite ? "#ef4444" : "var(--text-muted)", // red if favorite
                transition: "color 0.2s, transform 0.2s",
                transform: loading ? "scale(0.9)" : "scale(1)",
            }}
            title={isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle"}
        >
            <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                width="28"
                height="28"
                fill={isFavorite ? "currentColor" : "none"}
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
            >
                <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
            </svg>
        </button>
    );
}
