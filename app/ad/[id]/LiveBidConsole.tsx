"use client";

import { useState, useCallback, useEffect } from "react";
import { useDataChannel, useRoomContext } from "@livekit/components-react";
import { useSession } from "next-auth/react";

interface LiveBidConsoleProps {
    adId: string;
    isOwner: boolean;
    initialPrice: number;
    minStep: number;
}

export default function LiveBidConsole({ adId, isOwner, initialPrice, minStep }: LiveBidConsoleProps) {
    const { data: session } = useSession();
    const room = useRoomContext();

    // Live State
    const [currentPrice, setCurrentPrice] = useState(initialPrice);
    const [auctionStatus, setAuctionStatus] = useState<"IDLE" | "ACTIVE">("IDLE");
    const [highestBidderId, setHighestBidderId] = useState<string | null>(null);
    const [highestBidderName, setHighestBidderName] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const [lastBidId, setLastBidId] = useState<string | null>(null);
    const [flash, setFlash] = useState(false);

    useDataChannel((msg) => {
        try {
            const dataStr = new TextDecoder().decode(msg.payload);
            const dataObj = JSON.parse(dataStr);

            if (dataObj.type === "AUCTION_START") {
                setAuctionStatus("ACTIVE");
            } else if (dataObj.type === "AUCTION_END") {
                setAuctionStatus("IDLE");
            } else if (dataObj.type === "NEW_BID" || dataObj.type === "BID_ACCEPTED") {
                setCurrentPrice(dataObj.amount);
                setHighestBidderId(dataObj.userId || dataObj.bidderId);
                if (dataObj.userName || dataObj.bidderName) {
                    setHighestBidderName(dataObj.userName || dataObj.bidderName);
                }
                if (dataObj.bidId) setLastBidId(dataObj.bidId);

                setFlash(true);
                setTimeout(() => setFlash(false), 500);
            } else if (dataObj.type === "SYNC_STATE_RESPONSE") {
                if (dataObj.auctionStatus) setAuctionStatus(dataObj.auctionStatus);
                if (dataObj.liveHighestBid) setCurrentPrice(dataObj.liveHighestBid);
                if (dataObj.liveHighestBidderName) setHighestBidderName(dataObj.liveHighestBidderName);
            } else if (dataObj.type === "AUCTION_RESET") {
                setCurrentPrice(initialPrice);
                setHighestBidderId(null);
                setHighestBidderName(null);
                setLastBidId(null);
                setAuctionStatus("ACTIVE");
            }
        } catch (e) {
            // Ignore non-json
        }
    });

    const handleStartAuction = async () => {
        if (!room) return;
        setLoading(true);
        try {
            // Inform DB the auction is conceptually running (if tracking state is needed)
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: true }),
            });
            const payload = JSON.stringify({ type: "AUCTION_START" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("ACTIVE");
        } catch (e) {
            console.error("Error starting auction", e);
        }
        setLoading(false);
    };

    const handleStopAuction = async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: false }),
            });
            const payload = JSON.stringify({ type: "AUCTION_END" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("IDLE");
        } catch (e) {
            console.error("Error stopping auction", e);
        }
        setLoading(false);
    };

    const handleQuickBid = async (val: number) => {
        if (!session?.user?.id || auctionStatus !== "ACTIVE") return;
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/bid", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ roomId: adId, amount: currentPrice + val }),
            });
            const data = await res.json();
            if (!res.ok) alert(data.error || data.message || "Teklif verilemedi.");
        } catch (e) { console.error(e); alert("Bir hata oluştu."); }
        setLoading(false);
    };

    const placeBid = async () => {
        if (!session?.user?.id || auctionStatus !== "ACTIVE") return;

        const bidAmount = currentPrice + minStep;
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/bid", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ roomId: adId, amount: bidAmount }),
            });
            const data = await res.json();
            if (!res.ok) {
                alert(data.error || data.message || "Teklif verilemedi.");
            }
        } catch (e) {
            console.error(e);
            alert("Bir hata oluştu.");
        }
        setLoading(false);
    };

    // Auto-request sync on mount if viewer
    useEffect(() => {
        if (!isOwner && room) {
            const payload = JSON.stringify({ type: "REQUEST_SYNC_STATE" });
            room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true }).catch(console.error);
        }
    }, [isOwner, room]);

    const formatPrice = (p: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(p);

    if (isOwner) {
        return (
            <div className="flex flex-col gap-4 p-5 bg-black/40 border border-white/10 rounded-2xl shadow-xl relative overflow-hidden backdrop-blur-xl">
                <div className="flex flex-col items-center">
                    <span className="text-sm font-bold text-white/50 tracking-wider uppercase mb-4">Director Console</span>

                    <div className="flex flex-col gap-2 w-full">
                        {auctionStatus === "IDLE" ? (
                            <button disabled={loading} onClick={handleStartAuction} className="w-full bg-emerald-600 hover:bg-emerald-500 text-white font-black py-4 px-6 rounded-2xl shadow-[0_4px_25px_rgba(16,185,129,0.5)] text-xl uppercase tracking-widest transition-all">AÇIK ARTIRMAYI BAŞLAT</button>
                        ) : (
                            <>
                                <button disabled={loading || currentPrice <= initialPrice} className="w-full bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:bg-emerald-800 text-white font-black py-4 px-6 rounded-2xl shadow-lg text-xl uppercase tracking-widest transition-all">
                                    {loading ? "SATILIYOR..." : "KABUL ET VE SAT"}
                                </button>
                                <button disabled={loading} onClick={handleStopAuction} className="w-full bg-orange-500 hover:bg-orange-400 text-white font-bold py-3 px-6 rounded-xl shadow mt-2 text-sm uppercase transition-all">Durdur</button>
                            </>
                        )}
                    </div>
                </div>

                <div className={`flex flex-col p-4 bg-white rounded-xl border-2 ${flash ? "border-green-400 shadow-[0_0_15px_rgba(74,222,128,0.3)]" : "border-gray-100"} transition-all duration-300`}>
                    <span className="text-xs font-bold text-gray-400 mb-1">GÜNCEL FİYAT</span>
                    <div className="flex items-baseline gap-1">
                        <span className={`text-4xl font-black ${flash ? "text-green-500" : "text-gray-900"} transition-colors`}>{formatPrice(currentPrice)}</span>
                    </div>
                    {highestBidderName && (
                        <div className="mt-2 text-sm">
                            <span className="text-white/50 font-medium">LİDER: </span>
                            <span className="text-emerald-500 font-bold">{highestBidderName}</span>
                        </div>
                    )}
                </div>
            </div>
        );
    }

    // Viewer Mode
    const [amount, setAmount] = useState("");

    const handleCustomBid = async () => {
        if (!session?.user?.id || auctionStatus !== "ACTIVE" || !amount) return;
        const rawAmount = parseInt(amount.replace(/\./g, ""), 10);
        if (rawAmount <= currentPrice) {
            alert("Teklif güncel fiyattan yüksek olmalıdır.");
            return;
        }
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/bid", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ roomId: adId, amount: rawAmount }),
            });
            const data = await res.json();
            if (!res.ok) alert(data.error || data.message || "Teklif verilemedi.");
            else setAmount("");
        } catch (e) { console.error(e); alert("Bir hata oluştu."); }
        setLoading(false);
    };

    return (
        <div className="flex flex-col gap-4 p-5 bg-white/5 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl relative overflow-hidden">
            <div className="flex flex-col items-center justify-center py-4 relative z-10 w-full">
                <span className="text-xs font-bold text-white/50 tracking-widest uppercase mb-1 drop-shadow-md">GÜNCEL FİYAT</span>
                <span className="text-5xl font-black tabular-nums tracking-tighter text-emerald-400 mb-4" style={{ textShadow: "0 0 20px rgba(52, 211, 153, 0.4)" }}>
                    {formatPrice(currentPrice)}
                </span>
                {highestBidderName && (
                    <div className="mb-4 bg-black/40 px-4 py-1.5 rounded-full border border-white/10 text-sm shadow-sm backdrop-blur-md">
                        <span className="text-white/50 font-medium">LİDER: </span>
                        <span className="text-emerald-500 font-bold">{highestBidderName}</span>
                    </div>
                )}

                {/* Quick Bids */}
                <div className="flex flex-row gap-2 w-full mb-4">
                    {[50, 100, 500].map(val => (
                        <button
                            key={val}
                            type="button"
                            disabled={loading || auctionStatus !== "ACTIVE"}
                            onClick={() => handleQuickBid(val)}
                            className="flex-1 py-2 rounded-full bg-white/10 hover:bg-white/20 text-white font-bold text-sm transition-all shadow-lg backdrop-blur-md disabled:opacity-50 disabled:cursor-not-allowed border border-white/10"
                        >
                            +{val} ₺
                        </button>
                    ))}
                </div>

                {/* Premium Form */}
                <div className="flex w-full gap-2 items-center">
                    <input
                        type="text"
                        value={amount}
                        onChange={(e) => {
                            const val = e.target.value.replace(/[^0-9]/g, "");
                            setAmount(val ? new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)) : "");
                        }}
                        className="flex-[2] min-w-0 h-[50px] bg-white/10 backdrop-blur-md border border-white/20 focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 rounded-2xl px-4 text-white text-lg text-center font-black outline-none placeholder-white/30"
                        placeholder="Özel teklif gir"
                    />
                    <button
                        onClick={handleCustomBid}
                        disabled={loading || auctionStatus !== "ACTIVE" || !amount}
                        className="flex-[1] h-[50px] bg-emerald-600 hover:bg-emerald-500 disabled:bg-emerald-800 disabled:opacity-50 text-white border-0 rounded-2xl font-black text-sm tracking-wide transition-all shadow-lg truncate px-2"
                    >
                        {loading ? "..." : "TEKLİF VER"}
                    </button>
                </div>

                <div className="text-center mt-3 text-xs font-semibold text-white/40 flex items-center justify-center gap-1 w-full">
                    <span>Minimum Artırım:</span>
                    <span className="text-white/70">{formatPrice(minStep)}</span>
                </div>
            </div>
            {/* Background pattern */}
            <div className="absolute -bottom-10 -right-10 text-9xl opacity-[0.03] select-none pointer-events-none rotate-12">🔨</div>
        </div>
    );
}
