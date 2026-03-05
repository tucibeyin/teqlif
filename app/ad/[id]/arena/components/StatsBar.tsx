"use client";

import type { AuctionStatus } from "../types";

const STATS_BAR: React.CSSProperties = {
    background: "rgba(255, 255, 255, 0.7)",
    backdropFilter: "blur(15px)",
    borderRadius: "20px",
    border: "1px solid rgba(0, 180, 204, 0.2)",
    padding: "12px 16px",
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
};

const formatPrice = (val: number) =>
    new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

interface StatsBarProps {
    auctionStatus: AuctionStatus;
    highestBid: number;
    startingBid?: number | null;
    buyItNowPrice?: number | null;
    highestBidderName?: string | null;
    flashBid: boolean;
    notification?: string | null;
}

export function StatsBar({
    auctionStatus,
    highestBid,
    startingBid,
    buyItNowPrice,
    highestBidderName,
    flashBid,
    notification,
}: StatsBarProps) {
    const displayPrice = highestBid > 0 ? highestBid : (startingBid ?? 0);

    return (
        <div>
            {/* Notification banner */}
            {notification && (
                <div style={{
                    background: "rgba(0, 180, 204, 0.9)",
                    backdropFilter: "blur(10px)",
                    borderRadius: "12px",
                    padding: "8px 16px",
                    color: "white",
                    fontWeight: 800,
                    fontSize: "0.85rem",
                    textAlign: "center",
                    marginBottom: "8px",
                    animation: "fadeInUp 0.3s ease-out",
                }}>
                    {notification}
                </div>
            )}

            <div style={STATS_BAR}>
                <div style={{ display: "flex", flexDirection: "column" }}>
                    <span style={{ fontSize: "0.65rem", color: "rgba(0, 180, 204, 0.8)", fontWeight: 800, letterSpacing: "1px" }}>
                        {auctionStatus === "ACTIVE" ? "EN YÜKSEK TEKLİF" : "BAŞLANGIÇ FİYATI"}
                    </span>
                    <span style={{
                        fontSize: "1.4rem",
                        fontWeight: 900,
                        color: flashBid ? "#22c55e" : "#0f172a",
                        transition: "color 0.3s",
                    }}>
                        {formatPrice(displayPrice)}
                    </span>
                    {highestBidderName && (
                        <span style={{ fontSize: "0.7rem", color: "#64748b" }}>
                            👤 {highestBidderName}
                        </span>
                    )}
                </div>

                {buyItNowPrice && (
                    <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
                        <span style={{ fontSize: "0.65rem", color: "rgba(0, 180, 204, 0.8)", fontWeight: 800, letterSpacing: "1px" }}>
                            HEMEN AL
                        </span>
                        <span style={{ fontSize: "1rem", fontWeight: 800, color: "#0f172a" }}>
                            {formatPrice(buyItNowPrice)}
                        </span>
                    </div>
                )}
            </div>
        </div>
    );
}
