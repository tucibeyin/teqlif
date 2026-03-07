"use client";

import dynamic from "next/dynamic";

const LiveArena = dynamic(() => import("./LiveArena"), { ssr: false });

import { useState } from "react";

interface LiveArenaWrapperProps {
    roomId: string;
    adId: string;
    sellerId: string;
    isOwner: boolean;
    buyItNowPrice?: number | null;
    startingBid?: number | null;
    minBidStep?: number;
    initialHighestBid?: number;
    initialIsAuctionActive?: boolean;
    adOwnerName?: string;
    isQuickLive?: boolean;
}

export default function LiveArenaWrapper(props: LiveArenaWrapperProps) {
    const [hasJoined, setHasJoined] = useState(false);

    // Host (owner) autojoins. Viewers must click to join.
    if (!props.isOwner && !hasJoined) {
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
                borderRadius: "var(--radius-lg)"
            }}>
                <div style={{
                    width: "80px",
                    height: "80px",
                    borderRadius: "50%",
                    backgroundColor: "rgba(239, 68, 68, 0.2)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    marginBottom: "1rem"
                }}>
                    <span style={{ fontSize: "2rem" }}>🎥</span>
                </div>
                <h3 style={{ fontSize: "1.5rem", fontWeight: "bold", marginBottom: "0.5rem" }}>Canlı Yayın Aktif</h3>
                <p style={{ color: "var(--text-muted)", marginBottom: "2rem" }}>Yayına katılmak için butona tıklayın.</p>
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
                        transition: "transform 0.2s"
                    }}
                    onMouseOver={(e) => e.currentTarget.style.transform = "scale(1.05)"}
                    onMouseOut={(e) => e.currentTarget.style.transform = "scale(1)"}
                >
                    Canlı Yayına Katıl
                </button>
            </div>
        );
    }

    return <LiveArena {...props} />;
}
