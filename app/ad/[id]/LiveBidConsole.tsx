"use client";

import { useState, useCallback, useEffect } from "react";
import { useDataChannel, useRoomContext, useChat } from "@livekit/components-react";
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
    const { chatMessages, send } = useChat();

    // Live State
    const [currentPrice, setCurrentPrice] = useState(initialPrice);
    const [auctionStatus, setAuctionStatus] = useState<"IDLE" | "ACTIVE">("IDLE");
    const [highestBidderId, setHighestBidderId] = useState<string | null>(null);
    const [highestBidderName, setHighestBidderName] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const [lastBidId, setLastBidId] = useState<string | null>(null);
    const [flash, setFlash] = useState(false);
    const [countdown, setCountdown] = useState<number | null>(null);
    const [message, setMessage] = useState("");

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
            } else if (dataObj.type === "COUNTDOWN") {
                setCountdown(dataObj.value);
                if (dataObj.value === 0) {
                    setTimeout(() => setCountdown(null), 1000);
                }
            }
        } catch (e) {
            // Ignore non-json
        }
    });

    const handleStartAuction = useCallback(async () => {
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
    }, [room, adId]);

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

    const startCountdown = useCallback(async () => {
        if (!room) return;

        let counter = 10;
        setCountdown(counter);
        setAuctionStatus("ACTIVE"); // Show "Accept" and "Stop" immediately

        // Notify DB immediately so that "live" state triggers before countdown ends
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: true }),
            });
        } catch (e) { console.error(e); }

        const payloadStart = JSON.stringify({ type: "AUCTION_START" });
        await room.localParticipant.publishData(new TextEncoder().encode(payloadStart), { reliable: true });

        const payload = JSON.stringify({ type: "COUNTDOWN", value: counter });
        await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });

        const timer = setInterval(() => {
            counter--;
            if (counter >= 0) {
                setCountdown(counter);
                room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify({ type: "COUNTDOWN", value: counter })), { reliable: true });
            } else {
                clearInterval(timer);
                handleStartAuction();
            }
        }, 1000);
    }, [room, handleStartAuction]);

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
            const payload = JSON.stringify({ type: "SYNC_STATE_REQUEST" });
            room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true }).catch(console.error);
        }
    }, [isOwner, room]);

    const formatPrice = (p: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(p);

    const finalizeAuction = async () => {
        if (!lastBidId || !room) return;
        if (!confirm("Bu teklifi kabul edip satışı tamamlıyor musunuz?")) return;
        setLoading(true);
        try {
            const resAccept = await fetch(`/api/bids/${lastBidId}/accept`, { method: "PATCH" });
            if (resAccept.ok) {
                const resFinalize = await fetch(`/api/bids/${lastBidId}/finalize`, { method: "POST" });
                if (resFinalize.ok) {
                    const payloadSold = JSON.stringify({ type: "AUCTION_SOLD", winnerName: highestBidderName || "Katılımcı", price: currentPrice });
                    await room.localParticipant.publishData(new TextEncoder().encode(payloadSold), { reliable: true });

                    const payloadEnd = JSON.stringify({ type: "AUCTION_END" });
                    await room.localParticipant.publishData(new TextEncoder().encode(payloadEnd), { reliable: true });

                    fetch("/api/livekit/finalize", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ adId, winnerId: highestBidderId, finalPrice: currentPrice, isQuickLive: false }),
                    }).catch(console.error);

                    setAuctionStatus("IDLE");
                }
            }
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    };

    if (isOwner) {
        return (
            <div className="flex flex-col h-full gap-4">

                {/* Chat Area & Reactions Tray */}
                <div className="flex-[1_1_0] overflow-y-auto flex flex-col gap-2 pr-2 scrollbar-thin scrollbar-thumb-white/20 [mask-image:linear-gradient(to_bottom,transparent_0%,black_15%,black_100%)]">
                    {chatMessages.map((msg: any, idx: number) => (
                        <div key={idx} className="flex flex-col mb-1 break-words">
                            <span className="font-bold text-emerald-400 text-xs">
                                {msg.from?.name || "Anonim"}
                            </span>
                            <span className="text-white text-sm">
                                {msg.message}
                            </span>
                        </div>
                    ))}
                    {chatMessages.length === 0 && (
                        <div className="text-white/40 text-xs italic mt-auto">Sohbete ilk mesajı sen yaz...</div>
                    )}
                </div>

                {/* SOHBET INPUTU */}
                <form
                    onSubmit={(e) => {
                        e.preventDefault();
                        if (message.trim()) {
                            send(message);
                            setMessage("");
                        }
                    }}
                    className="w-full min-h-[50px] flex items-center gap-2 bg-black/50 backdrop-blur-md border border-white/10 rounded-full px-4 pr-1 shrink-0"
                >
                    <input
                        type="text"
                        value={message}
                        onChange={(e) => setMessage(e.target.value)}
                        placeholder="Sohbet et..."
                        className="bg-transparent border-none outline-none text-white flex-1 text-[0.95rem] min-w-0"
                    />
                    <button type="submit" className="shrink-0 bg-emerald-400 text-black border-none rounded-full w-[38px] h-[38px] font-bold flex items-center justify-center active:scale-90 transition-transform">
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
                    </button>
                </form>

                <div className="flex flex-col gap-4 p-5 bg-black/40 border border-white/10 rounded-2xl shadow-xl shrink-0 backdrop-blur-xl">
                    <div className="flex flex-col items-center">
                        <span className="text-sm font-bold text-white/50 tracking-wider uppercase mb-4">Director Console</span>

                        <div className="flex flex-col gap-2 w-full">
                            {auctionStatus === "IDLE" ? (
                                <button disabled={loading} onClick={startCountdown} className="w-full bg-emerald-600 hover:bg-emerald-500 text-white font-black py-4 px-6 rounded-2xl shadow-[0_4px_25px_rgba(16,185,129,0.5)] text-xl uppercase tracking-widest transition-all">AÇIK ARTIRMAYI BAŞLAT</button>
                            ) : (
                                <>
                                    <button disabled={loading || currentPrice <= initialPrice} onClick={finalizeAuction} className="w-full bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:bg-emerald-800 text-white font-black py-4 px-6 rounded-2xl shadow-lg text-xl uppercase tracking-widest transition-all">
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
        <div className="flex flex-col h-full gap-4">

            {/* Chat Area & Reactions Tray */}
            <div className="flex-[1_1_0] overflow-y-auto flex flex-col gap-2 pr-2 scrollbar-thin scrollbar-thumb-white/20 [mask-image:linear-gradient(to_bottom,transparent_0%,black_15%,black_100%)]">
                {chatMessages.map((msg: any, idx: number) => (
                    <div key={idx} className="flex flex-col mb-1 break-words">
                        <span className="font-bold text-emerald-400 text-xs">
                            {msg.from?.name || "Anonim"}
                        </span>
                        <span className="text-white text-sm">
                            {msg.message}
                        </span>
                    </div>
                ))}
                {chatMessages.length === 0 && (
                    <div className="text-white/40 text-xs italic mt-auto">Sohbete ilk mesajı sen yaz...</div>
                )}
            </div>

            {/* SOHBET INPUTU */}
            <form
                onSubmit={(e) => {
                    e.preventDefault();
                    if (message.trim()) {
                        send(message);
                        setMessage("");
                    }
                }}
                className="w-full min-h-[50px] flex items-center gap-2 bg-black/50 backdrop-blur-md border border-white/10 rounded-full px-4 pr-1 shrink-0"
            >
                <input
                    type="text"
                    value={message}
                    onChange={(e) => setMessage(e.target.value)}
                    placeholder="Sohbet et..."
                    className="bg-transparent border-none outline-none text-white flex-1 text-[0.95rem] min-w-0"
                />
                <button type="submit" className="shrink-0 bg-emerald-400 text-black border-none rounded-full w-[38px] h-[38px] font-bold flex items-center justify-center active:scale-90 transition-transform">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
                </button>
            </form>

            <div className="flex flex-col gap-4 p-5 bg-white/5 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl relative overflow-hidden shrink-0">
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
        </div>
    );
}
