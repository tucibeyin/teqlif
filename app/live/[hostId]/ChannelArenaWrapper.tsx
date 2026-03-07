"use client";

import dynamic from "next/dynamic";
import { useState } from "react";

const ChannelArena = dynamic(() => import("./ChannelArena"), { ssr: false });

interface Props {
    hostId: string;
    hostName: string;
    isOwner: boolean;
}

export default function ChannelArenaWrapper({ hostId, hostName, isOwner }: Props) {
    // Host otomatik girer; izleyiciler onay ekranı görür.
    const [hasJoined, setHasJoined] = useState(isOwner);

    if (!hasJoined) {
        return (
            <div style={{
                width: "100%",
                height: "600px",
                backgroundColor: "#000",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                color: "white",
                borderRadius: "var(--radius-lg)",
                gap: "1rem",
            }}>
                <div style={{
                    width: "80px",
                    height: "80px",
                    borderRadius: "50%",
                    backgroundColor: "rgba(239, 68, 68, 0.2)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                }}>
                    <span style={{ fontSize: "2rem" }}>📺</span>
                </div>
                <h3 style={{ fontSize: "1.5rem", fontWeight: "bold", margin: 0 }}>
                    {hostName} Canlı Yayında
                </h3>
                <p style={{ color: "var(--text-muted)", margin: 0 }}>
                    Yayına katılmak için butona tıklayın.
                </p>
                <button
                    onClick={() => setHasJoined(true)}
                    style={{
                        padding: "1rem 2rem",
                        fontSize: "1.1rem",
                        fontWeight: "bold",
                        backgroundColor: "#ef4444",
                        color: "white",
                        border: "none",
                        borderRadius: "2rem",
                        cursor: "pointer",
                        boxShadow: "0 4px 15px rgba(239, 68, 68, 0.4)",
                        transition: "transform 0.2s",
                    }}
                    onMouseOver={(e) => (e.currentTarget.style.transform = "scale(1.05)")}
                    onMouseOut={(e) => (e.currentTarget.style.transform = "scale(1)")}
                >
                    Canlı Yayına Katıl
                </button>
            </div>
        );
    }

    return <ChannelArena hostId={hostId} hostName={hostName} isOwner={isOwner} />;
}
