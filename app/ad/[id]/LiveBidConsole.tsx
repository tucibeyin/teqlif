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
            <div className="flex flex-col gap-4 p-5 bg-red-50 border border-red-100 rounded-xl shadow-sm">
                <div className="flex justify-between items-center">
                    <div>
                        <span className="text-sm font-bold text-red-800 tracking-wide uppercase">Host Kontrol Paneli</span>
                        <div className="flex items-center gap-2 mt-1 hidden">
                            <span className={`w-2 h-2 rounded-full ${auctionStatus === "ACTIVE" ? "bg-green-500 animate-pulse" : "bg-gray-400"}`}></span>
                            <span className="text-xs font-semibold text-gray-600">{auctionStatus === "ACTIVE" ? "Açık Arttırma Aktif" : "Beklemede"}</span>
                        </div>
                    </div>
                    {auctionStatus === "ACTIVE" ? (
                        <button disabled={loading} onClick={handleStopAuction} className="bg-orange-500 hover:bg-orange-600 text-white font-bold py-2 px-4 rounded-lg shadow transition-colors text-sm">⛔ Durdur</button>
                    ) : (
                        <button disabled={loading} onClick={handleStartAuction} className="bg-red-600 hover:bg-red-700 text-white font-bold py-2 px-4 rounded-lg shadow transition-colors text-sm">▶️ Başlat</button>
                    )}
                </div>

                <div className={`flex flex-col p-4 bg-white rounded-xl border-2 ${flash ? "border-green-400 shadow-[0_0_15px_rgba(74,222,128,0.3)]" : "border-gray-100"} transition-all duration-300`}>
                    <span className="text-xs font-bold text-gray-400 mb-1">GÜNCEL FİYAT</span>
                    <div className="flex items-baseline gap-1">
                        <span className={`text-4xl font-black ${flash ? "text-green-500" : "text-gray-900"} transition-colors`}>{formatPrice(currentPrice)}</span>
                    </div>
                    {highestBidderName && (
                        <div className="mt-2 text-sm">
                            <span className="text-gray-500 font-medium">Lider: </span>
                            <span className="text-green-600 font-bold">{highestBidderName}</span>
                        </div>
                    )}
                </div>
            </div>
        );
    }

    // Viewer Mode
    return (
        <div className="flex flex-col gap-4 p-5 bg-white border border-gray-200 rounded-xl shadow-lg relative overflow-hidden">
            <div className="flex justify-between items-start mb-2 relative z-10">
                <div className="flex flex-col">
                    <div className="flex items-center gap-2 mb-1">
                        <span className={`w-2.5 h-2.5 rounded-full ${auctionStatus === "ACTIVE" ? "bg-red-500 animate-pulse" : "bg-amber-500"}`}></span>
                        <span className="text-xs font-bold tracking-wider text-gray-500 uppercase">{auctionStatus === "ACTIVE" ? "CANLI TEKLİF AÇIK" : "YAYINCI BEKLENİYOR"}</span>
                    </div>
                </div>
            </div>

            <div className="flex flex-col items-center justify-center py-6 bg-gray-50 rounded-xl border border-gray-100 relative z-10">
                <span className="text-sm font-bold text-gray-400 uppercase tracking-widest mb-2">Güncel Fiyat</span>
                <span className={`text-5xl font-black tabular-nums tracking-tighter ${flash ? "text-green-500 scale-110" : "text-gray-900"} transition-all duration-300`}>
                    {formatPrice(currentPrice)}
                </span>
                {highestBidderName && (
                    <div className="mt-3 bg-white px-4 py-1.5 rounded-full border border-gray-200 text-sm shadow-sm">
                        <span className="text-gray-500 font-medium">Lider: </span>
                        <span className="text-green-600 font-bold">{highestBidderName}</span>
                    </div>
                )}
            </div>

            <div className="relative z-10 mt-2">
                <button
                    disabled={loading || auctionStatus !== "ACTIVE"}
                    onClick={placeBid}
                    className={`w-full py-5 rounded-2xl text-xl font-black tracking-wide text-white shadow-xl transition-all transform active:scale-[0.98] flex items-center justify-center gap-3 ${auctionStatus === "ACTIVE" && !loading
                            ? "bg-gradient-to-r from-red-600 to-red-500 hover:from-red-500 hover:to-red-400 shadow-red-500/30"
                            : "bg-gray-300 shadow-none text-gray-500 cursor-not-allowed"
                        }`}
                >
                    {loading ? (
                        <div className="w-6 h-6 border-4 border-white/30 border-t-white rounded-full animate-spin"></div>
                    ) : (
                        <>
                            <span>{formatPrice(currentPrice + minStep)}</span>
                            <span className="text-lg opacity-80 uppercase tracking-wider font-bold">TEKLİF VER</span>
                        </>
                    )}
                </button>
                <div className="text-center mt-3 text-xs font-semibold text-gray-400 flex items-center justify-center gap-1">
                    <span>Otomatik artırım:</span>
                    <span className="text-gray-600">{formatPrice(minStep)}</span>
                </div>
            </div>

            {/* Background pattern */}
            <div className="absolute -bottom-10 -right-10 text-9xl opacity-[0.03] select-none pointer-events-none rotate-12">🔨</div>
        </div>
    );
}
