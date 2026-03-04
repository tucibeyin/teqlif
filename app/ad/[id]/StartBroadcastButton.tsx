"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface StartBroadcastButtonProps {
    adId: string;
}

export default function StartBroadcastButton({ adId }: StartBroadcastButtonProps) {
    const router = useRouter();
    const [isLoading, setIsLoading] = useState(false);

    const handleStartLive = async () => {
        if (!confirm("Canlı yayını başlatmak istediğinize emin misiniz? Tarayıcınız kamera ve mikrofon erişimi isteyecektir.")) return;

        setIsLoading(true);
        try {
            const res = await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isLive: true, liveKitRoomId: adId, isAuctionActive: false }),
            });

            if (res.ok) {
                router.refresh();
            } else {
                alert("Yayın başlatılamadı.");
            }
        } catch (error) {
            console.error("Yayın başlatma hatası:", error);
            alert("Bağlantı hatası.");
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <button
            onClick={handleStartLive}
            disabled={isLoading}
            style={{
                width: "100%",
                padding: "1rem",
                marginTop: "1rem",
                background: "linear-gradient(135deg, #ef4444 0%, #b91c1c 100%)",
                color: "white",
                border: "none",
                borderRadius: "var(--radius-md)",
                fontSize: "1.1rem",
                fontWeight: 700,
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "0.5rem",
                boxShadow: "0 4px 15px rgba(239, 68, 68, 0.4)",
                transition: "transform 0.2s"
            }}
        >
            {isLoading ? (
                <span style={{ display: "inline-block", width: "20px", height: "20px", border: "2px solid white", borderTopColor: "transparent", borderRadius: "50%", animation: "spin 1s linear infinite" }}></span>
            ) : (
                <>
                    <span style={{ display: "inline-block", width: "10px", height: "10px", borderRadius: "50%", background: "white", animation: "pulse 1.5s infinite" }}></span>
                    Canlı Yayın Başlat
                </>
            )}
        </button>
    );
}
