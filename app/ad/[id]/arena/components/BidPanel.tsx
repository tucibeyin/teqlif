"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";

const formatPrice = (val: number) =>
    new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

interface BidPanelProps {
    adId: string;
    sellerId: string;
    currentHighest: number;
    minStep: number;
    startingBid?: number | null;
    buyItNowPrice?: number | null;
    isAuctionActive: boolean;
    isOwner: boolean;
    lastAcceptedBidId?: string | null;
    highestBidderId?: string | null;
    onAccept?: () => void;
    onReject?: () => void;
    onBuyNow?: () => void;
    loading?: boolean;
}

export function BidPanel({
    adId,
    sellerId,
    currentHighest,
    minStep,
    startingBid,
    buyItNowPrice,
    isAuctionActive,
    isOwner,
    lastAcceptedBidId,
    highestBidderId,
    onAccept,
    onReject,
    onBuyNow,
    loading = false,
}: BidPanelProps) {
    const router = useRouter();
    const [amount, setAmount] = useState("");
    const [bidLoading, setBidLoading] = useState(false);
    const [status, setStatus] = useState<{ type: "success" | "error"; msg: string } | null>(null);

    const nextMin = currentHighest > 0 ? currentHighest + minStep : (startingBid ?? minStep);

    useEffect(() => {
        setAmount(nextMin.toString());
    }, [nextMin]);

    const handleBid = async (e: React.FormEvent) => {
        e.preventDefault();
        const numAmount = parseFloat(amount.replace(/\./g, "").replace(",", "."));
        if (isNaN(numAmount) || numAmount < nextMin) {
            setStatus({ type: "error", msg: `Minimum teklif: ${formatPrice(nextMin)}` });
            return;
        }
        setBidLoading(true);
        try {
            const res = await fetch(`/api/ads/${adId}/bid`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ amount: numAmount }),
            });
            const data = await res.json();
            if (res.ok) {
                setStatus({ type: "success", msg: "✅ Teklifiniz iletildi!" });
                setTimeout(() => setStatus(null), 3000);
            } else {
                setStatus({ type: "error", msg: data.error || "Hata oluştu." });
            }
        } catch {
            setStatus({ type: "error", msg: "Bağlantı hatası." });
        } finally {
            setBidLoading(false);
        }
    };

    return (
        <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            {/* Host: accept / reject */}
            {isOwner && lastAcceptedBidId == null && currentHighest > 0 && (
                <div style={{ display: "flex", gap: "8px" }}>
                    <button
                        onClick={onAccept}
                        disabled={loading}
                        style={{
                            flex: 1,
                            padding: "12px",
                            background: "rgba(34,197,94,0.8)",
                            border: "none",
                            borderRadius: "16px",
                            color: "white",
                            fontWeight: 900,
                            cursor: "pointer",
                            fontSize: "0.9rem",
                        }}
                    >
                        ✅ KABUL ET
                    </button>
                    <button
                        onClick={onReject}
                        disabled={loading}
                        style={{
                            flex: 1,
                            padding: "12px",
                            background: "rgba(239,68,68,0.8)",
                            border: "none",
                            borderRadius: "16px",
                            color: "white",
                            fontWeight: 900,
                            cursor: "pointer",
                            fontSize: "0.9rem",
                        }}
                    >
                        ❌ REDDET
                    </button>
                </div>
            )}

            {/* Viewer: bid form */}
            {!isOwner && isAuctionActive && (
                <form onSubmit={handleBid} style={{ display: "flex", gap: "8px" }}>
                    <input
                        value={amount}
                        onChange={(e) => {
                            const raw = e.target.value.replace(/\D/g, "");
                            setAmount(raw ? new Intl.NumberFormat("tr-TR").format(parseInt(raw, 10)) : "");
                        }}
                        className="flex-[2] min-w-0 h-[50px] bg-white/10 backdrop-blur-md border border-white/20 focus:border-emerald-500 rounded-2xl px-4 text-white text-lg text-center font-black outline-none placeholder-white/30 transition-all"
                        placeholder="Özel teklif"
                    />
                    <button
                        type="submit"
                        disabled={bidLoading || !amount}
                        className="flex-[1] h-[50px] bg-emerald-600 hover:bg-emerald-500 disabled:bg-emerald-800 disabled:opacity-50 text-white border-0 rounded-2xl font-black tracking-wide transition-all shadow-lg active:scale-95"
                    >
                        {bidLoading ? "..." : "TEKLİF VER"}
                    </button>
                </form>
            )}

            {/* Status feedback */}
            {status && (
                <div style={{
                    padding: "10px 16px",
                    borderRadius: "12px",
                    background: status.type === "success" ? "rgba(34,197,94,0.2)" : "rgba(239,68,68,0.2)",
                    color: status.type === "success" ? "#22c55e" : "#f87171",
                    fontWeight: 700,
                    fontSize: "0.85rem",
                    textAlign: "center",
                }}>
                    {status.msg}
                </div>
            )}

            {/* Buy now */}
            {!isOwner && buyItNowPrice && (
                <button
                    onClick={onBuyNow}
                    disabled={loading}
                    style={{
                        width: "100%",
                        padding: "14px",
                        background: "linear-gradient(135deg, #00B4CC, #008da1)",
                        border: "none",
                        borderRadius: "16px",
                        color: "white",
                        fontWeight: 900,
                        cursor: "pointer",
                        fontSize: "1rem",
                        boxShadow: "0 4px 15px rgba(0,180,204,0.4)",
                    }}
                >
                    ⚡ Hemen Al — {formatPrice(buyItNowPrice)}
                </button>
            )}
        </div>
    );
}
