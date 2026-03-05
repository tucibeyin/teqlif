"use client";

import { useEffect, useState, useCallback } from "react";
import confetti from "canvas-confetti";
import { LiveKitRoom, RoomAudioRenderer, useTracks, VideoTrack, useDataChannel, useRoomContext, useChat, TrackToggle, useConnectionState, useParticipants } from "@livekit/components-react";
import { Track, ConnectionState } from "livekit-client";
import "@livekit/components-styles";
import { useSession } from "next-auth/react";
import { useRouter } from "next/navigation";

interface LiveArenaProps {
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

export default function LiveArena({
    roomId,
    adId,
    sellerId,
    isOwner,
    buyItNowPrice,
    startingBid,
    minBidStep = 1,
    initialHighestBid = 0,
    initialIsAuctionActive = false,
    adOwnerName = "Satıcı",
    isQuickLive = false
}: LiveArenaProps) {
    const { data: session } = useSession();
    const [token, setToken] = useState("");
    const [role, setRole] = useState("viewer");
    const [wantsToPublish, setWantsToPublish] = useState(isOwner);

    const fetchToken = useCallback(async (currentRole: string) => {
        try {
            const resp = await fetch(`/api/livekit/token?room=${roomId}${currentRole === "guest" ? "&role=guest" : ""}`);
            const data = await resp.json();
            setToken(data.token);
            if (currentRole === "guest") {
                setWantsToPublish(true);
            }
        } catch (e) {
            console.error("LiveKit token hatası:", e);
        }
    }, [roomId]);

    useEffect(() => {
        if (!session?.user?.id) return;
        fetchToken(role);
    }, [roomId, session, role, fetchToken]);

    if (!token) {
        return (
            <div style={{ padding: "2rem", textAlign: "center", background: "var(--bg-secondary)", borderRadius: "var(--radius-lg)" }}>
                <p>Canlı yayına bağlanılıyor...</p>
            </div>
        );
    }

    return (
        <LiveKitRoom
            video={wantsToPublish}
            audio={wantsToPublish}
            token={token}
            serverUrl={process.env.NEXT_PUBLIC_LIVEKIT_URL}
            data-lk-theme="default"
            className="w-full h-[100dvh] bg-neutral-950"
        >
            <CustomArenaLayout
                adId={adId}
                sellerId={sellerId}
                isOwner={isOwner}
                buyItNowPrice={buyItNowPrice}
                startingBid={startingBid}
                minBidStep={minBidStep}
                initialHighestBid={initialHighestBid}
                initialIsAuctionActive={initialIsAuctionActive}
                role={role}
                wantsToPublish={wantsToPublish}
                adOwnerName={adOwnerName}
            />
            <RoomAudioRenderer />
            {!isOwner && <CoHostListener setRole={setRole} setWantsToPublish={setWantsToPublish} />}
        </LiveKitRoom>
    );
}

function CustomArenaLayout({
    adId,
    sellerId,
    isOwner,
    buyItNowPrice,
    startingBid,
    minBidStep,
    initialHighestBid,
    initialIsAuctionActive,
    role,
    wantsToPublish,
    adOwnerName,
    isQuickLive
}: any) {
    const room = useRoomContext();
    const { chatMessages, send } = useChat();
    const router = useRouter();
    const { data: session } = useSession();
    const tracks = useTracks([Track.Source.Camera]);
    const participants = useParticipants();
    const participantCount = participants.length;
    const [liveHighestBid, setLiveHighestBid] = useState(initialHighestBid);
    const [lastAcceptedBidId, setLastAcceptedBidId] = useState<string | null>(null);
    const [liveHighestBidId, setLiveHighestBidId] = useState<string | null>(null);
    const [auctionStatus, setAuctionStatus] = useState<"IDLE" | "ACTIVE">(initialIsAuctionActive ? "ACTIVE" : "IDLE");
    const [auctionNotification, setAuctionNotification] = useState<string | null>(null);
    const [messages, setMessages] = useState<{ id: string, text: string, sender: string, senderId?: string }[]>([]);
    const [liveHighestBidderId, setLiveHighestBidderId] = useState<string | null>(null);
    const [liveHighestBidderName, setLiveHighestBidderName] = useState<string | null>(null);
    const [stageRequests, setStageRequests] = useState<{ id: string; name: string }[]>([]);
    const connectionState = useConnectionState();
    const [isRoomClosed, setIsRoomClosed] = useState(false);
    const [flashBid, setFlashBid] = useState(false);
    const [message, setMessage] = useState("");

    // Finalization overlay state
    const [finalizedWinner, setFinalizedWinner] = useState<string | null>(null);
    const [finalizedAmount, setFinalizedAmount] = useState<number | null>(null);
    const [showFinalization, setShowFinalization] = useState(false);

    // Permanent auction result state (set on AUCTION_SOLD, never cleared)
    const [auctionResult, setAuctionResult] = useState<{ winnerName: string; price: number } | null>(null);
    const [showSoldOverlay, setShowSoldOverlay] = useState<boolean>(true);

    // Confetti cannon — fires from both bottom corners toward center
    const fireConfetti = useCallback(() => {
        const opts = {
            particleCount: 140,
            spread: 75,
            startVelocity: 55,
            gravity: 0.8,
            colors: ['#FFD700', '#FFA500', '#FF6B35', '#00B4CC', '#FFFFFF', '#22c55e'],
        };
        confetti({ ...opts, origin: { x: 0.05, y: 1 }, angle: 65 });
        confetti({ ...opts, origin: { x: 0.95, y: 1 }, angle: 115 });
        // Second wave for more drama
        setTimeout(() => {
            confetti({ ...opts, particleCount: 80, origin: { x: 0.2, y: 0.8 }, angle: 80 });
            confetti({ ...opts, particleCount: 80, origin: { x: 0.8, y: 0.8 }, angle: 100 });
        }, 400);
    }, []);

    // Countdown Gamification
    const [countdown, setCountdown] = useState(0);

    // Reactions State
    const [reactions, setReactions] = useState<{ id: string, emoji: string, left: number }[]>([]);
    const [lastReactionTime, setLastReactionTime] = useState(0);
    const [loading, setLoading] = useState(false);

    const formattedPrice = (val: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

    const handleAccept = useCallback(async () => {
        if (!liveHighestBidId) return;
        if (!confirm("Dikkat! Bu teqlifi kabul edip satışı tamamlıyorsunuz?")) return;
        setLoading(true);
        try {
            const resAccept = await fetch(`/api/bids/${liveHighestBidId}/accept`, { method: "PATCH" });
            if (resAccept.ok) {
                let finalizeSuccess = false;
                if (!isQuickLive) {
                    const resFinalize = await fetch(`/api/bids/${liveHighestBidId}/finalize`, { method: "POST" });
                    finalizeSuccess = resFinalize.ok;
                } else {
                    finalizeSuccess = true;
                }

                if (finalizeSuccess) {
                    // 1️⃣ Broadcast AUCTION_SOLD signal to all room participants (DataChannel)
                    if (room) {
                        const soldPayload = JSON.stringify({
                            type: "AUCTION_SOLD",
                            winnerId: liveHighestBidderId,
                            winnerName: liveHighestBidderName || liveHighestBidderId || "Katılımcı",
                            price: liveHighestBid,
                        });
                        room.localParticipant.publishData(new TextEncoder().encode(soldPayload), { reliable: true });

                        const payloadEnd = JSON.stringify({ type: "AUCTION_END" });
                        room.localParticipant.publishData(new TextEncoder().encode(payloadEnd), { reliable: true });

                        const payloadFinalized = JSON.stringify({
                            type: "SALE_FINALIZED",
                            winnerName: liveHighestBidderName || liveHighestBidderId || "Katılımcı",
                            amount: liveHighestBid
                        });
                        room.localParticipant.publishData(new TextEncoder().encode(payloadFinalized), { reliable: true });
                    }

                    // 2️⃣ Call the secure finalize endpoint (marks Ad as SOLD, sends winner FCM)
                    if (liveHighestBidderId) {
                        fetch("/api/livekit/finalize", {
                            method: "POST",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({
                                adId,
                                winnerId: liveHighestBidderId,
                                finalPrice: liveHighestBid,
                                isQuickLive
                            }),
                        }).catch((e) => console.error("[FINALIZE] Error:", e));
                    }

                    setCountdown(0);
                    setAuctionStatus("IDLE");
                }
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    }, [liveHighestBidId, liveHighestBidderId, liveHighestBidderName, liveHighestBid, room, adId]);


    const handleReject = useCallback(async () => {
        if (!liveHighestBidId) return;
        if (!confirm("Bu teqlifi reddetmek istediğinize emin misiniz?")) return;
        setLoading(true);
        try {
            const res = await fetch(`/api/bids/${liveHighestBidId}/reject`, { method: "PATCH" });
            if (res.ok) {
                // Clear state locally
                setLiveHighestBid(initialHighestBid);
                setLiveHighestBidId(null);
                setLiveHighestBidderId(null);
                setLiveHighestBidderName(null);

                // Broadcast update to others
                if (room) {
                    const payload = JSON.stringify({
                        type: "BID_REJECTED",
                        bidId: liveHighestBidId,
                        bidderId: liveHighestBidderId
                    });
                    room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                }
                alert("teqlif reddedildi.");
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    }, [liveHighestBidId, room, initialHighestBid]);

    const handleEndBroadcast = async (skipConfirm = false) => {
        if (!skipConfirm && !confirm("Yayını bitirmek istiyor musunuz?")) return;
        setLoading(true);
        try {
            if (room) {
                const payload = JSON.stringify({ type: "ROOM_CLOSED" });
                await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            }
            const res = await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isLive: false }),
            });
            if (res.ok) {
                room?.disconnect();
                router.refresh();
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    };

    const handleResetAuction = async () => {
        if (!room) return;
        setLoading(true);
        try {
            const res = await fetch('/api/livekit/reset', {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId })
            });
            if (res.ok) {
                const payload = JSON.stringify({ type: "AUCTION_RESET" });
                await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            }
        } catch (err) {
            console.error("Reset Auction Error:", err);
        } finally {
            setLoading(false);
        }
    };

    const handleBuyNow = async () => {
        if (!buyItNowPrice) return;
        setLoading(true);
        try {
            const res = await fetch("/api/conversations", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ userId: sellerId, adId }),
            });
            if (res.ok) {
                const conversation = await res.json();
                router.push(`/dashboard/messages?id=${conversation.id}`);
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    };




    const isBroadcastEnded = isRoomClosed || connectionState === ConnectionState.Disconnected;

    const addReaction = useCallback((emoji: string) => {
        const newReaction = { id: Date.now().toString() + Math.random(), emoji, left: Math.random() * 15 + 75 }; // Between 75% and 90%
        setReactions(prev => [...prev.slice(-15), newReaction]); // Max 15 emojis simultaneously
        setTimeout(() => {
            setReactions(prev => prev.filter(r => r.id !== newReaction.id));
        }, 2500);
    }, []);

    const handleReaction = useCallback(async (emoji: string) => {
        const now = Date.now();
        if (now - lastReactionTime < 500) return; // Rate limit: max 2 clicks per sec
        setLastReactionTime(now);

        if (!room) return;
        const payload = JSON.stringify({ type: "REACTION", emoji, userId: session?.user?.id });
        try {
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            addReaction(emoji); // Local echo
        } catch (e) {
            console.error("Reaction send error:", e);
        }
    }, [room, lastReactionTime, session, addReaction]);

    const handleStartAuction = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: true }),
            });
            const payload = JSON.stringify({ type: "AUCTION_START" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("ACTIVE");
            setAuctionNotification("📣 AÇIK ARTTIRMA BAŞLADI!");
            setTimeout(() => setAuctionNotification(null), 4000);
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    }, [room, adId]);

    const handleStopAuction = useCallback(async () => {
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
            setAuctionNotification("📣 AÇIK ARTTIRMA DURDURULDU");
            setTimeout(() => setAuctionNotification(null), 4000);
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    }, [room, adId]);

    useDataChannel((msg) => {

        try {
            const dataStr = new TextDecoder().decode(msg.payload);

            // Enforcing JSON standard payloads (legacy string parsing removed)

            const dataObj = JSON.parse(dataStr);
            if (dataObj.type === 'NEW_BID') {
                setLiveHighestBid(dataObj.amount);
                setLiveHighestBidId(dataObj.bidId); // TRUTH: Save exact ID
                setLiveHighestBidderId(dataObj.bidderId);
                if (dataObj.bidderName) setLiveHighestBidderName(dataObj.bidderName);
                setLastAcceptedBidId(null);
                setFlashBid(true);
                setTimeout(() => setFlashBid(false), 300);
            } else if (dataObj.type === 'BID_ACCEPTED') {
                setLiveHighestBid(dataObj.amount);
                setLiveHighestBidId(dataObj.bidId);
                setLiveHighestBidderId(dataObj.bidderId);
                if (dataObj.bidderName) setLiveHighestBidderName(dataObj.bidderName);
                setLastAcceptedBidId(dataObj.bidId);
                setFlashBid(true);
                setTimeout(() => setFlashBid(false), 300);
            } else if (dataObj.type === 'BID_REJECTED') {
                if (session?.user?.id === dataObj.bidderId) {
                    alert("Teklifiniz satıcı tarafından reddedildi.");
                }
                setLiveHighestBid(initialHighestBid);
                setLiveHighestBidId(null);
                setLiveHighestBidderId(null);
                setLiveHighestBidderName(null);

                setAuctionNotification("📣 Son Teklif Reddedildi");
                setTimeout(() => setAuctionNotification(null), 3000);
            } else if (dataObj.type === 'SYNC_STATE_RESPONSE') {
                if (dataObj.auctionStatus) setAuctionStatus(dataObj.auctionStatus);
                if (dataObj.liveHighestBid) setLiveHighestBid(dataObj.liveHighestBid);
                if (dataObj.liveHighestBidderName) setLiveHighestBidderName(dataObj.liveHighestBidderName);

            } else if (dataObj.type === 'REACTION') {
                addReaction(dataObj.emoji);
            } else if (dataObj.type === 'AUCTION_START') {
                setAuctionStatus("ACTIVE");
                setAuctionNotification("📣 AÇIK ARTTIRMA BAŞLADI!");
                setTimeout(() => setAuctionNotification(null), 4000);
            } else if (dataObj.type === 'AUCTION_RESET') {
                setLiveHighestBid(initialHighestBid);
                setLiveHighestBidId(null);
                setLiveHighestBidderId(null);
                setLiveHighestBidderName(null);
                setAuctionStatus("IDLE");
                setAuctionResult(null);
                setShowSoldOverlay(false);
                setFinalizedWinner(null);
                setFinalizedAmount(null);
                setShowFinalization(false);
                setCountdown(0);

                // Optional: show a notification that bids were reset
                setAuctionNotification("📣 Yeni Ürüne Geçildi! Teklif Bekleniyor...");
                setTimeout(() => setAuctionNotification(null), 4000);
            } else if (dataObj.type === 'AUCTION_END') {
                setAuctionStatus("IDLE");
                setAuctionNotification("📣 AÇIK ARTTIRMA DURDURULDU");
                setTimeout(() => setAuctionNotification(null), 4000);
            } else if (dataObj.type === 'ROOM_CLOSED') {
                setIsRoomClosed(true);
            } else if (dataObj.type === 'COUNTDOWN') {
                setCountdown(dataObj.value);
            } else if (dataObj.type === 'REQUEST_STAGE') {
                if (dataObj.userId) {
                    setStageRequests(prev => {
                        if (prev.find(r => r.id === dataObj.userId)) return prev;
                        return [...prev, { id: dataObj.userId, name: dataObj.userName || "Katılımcı" }];
                    });
                }
            } else if (dataObj.type === 'SALE_FINALIZED') {
                setFinalizedWinner(dataObj.winnerName || "Katılımcı");
                setFinalizedAmount(dataObj.amount);
                setShowFinalization(true);

                // Add automated system message
                const msg = {
                    id: Date.now().toString(),
                    text: `🎉 Tebrikler! Ürün ${new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(dataObj.amount || 0)} bedel ile satıldı!`,
                    sender: "SİSTEM"
                };
                setMessages(prev => [...prev.slice(-10), msg]);
                setTimeout(() => {
                    setShowFinalization(false);
                }, 10000); // hide overlay after 10s
            } else if (dataObj.type === 'AUCTION_SOLD') {
                // 🎊 Permanent auction result — sets the SATILDI overlay and fires confetti
                const winner = dataObj.winnerName || "Katılımcı";
                const price = Number(dataObj.price) || 0;
                setAuctionResult({ winnerName: winner, price });
                setShowSoldOverlay(true);
                setAuctionStatus("IDLE");
                fireConfetti();
            }
        } catch (e) {
            // Ignore non-json
        }
    });

    const startCountdown = useCallback(() => {
        if (!room) return;

        let counter = 10;
        setCountdown(counter);

        // Broadcast initial
        room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify({ type: "COUNTDOWN", value: counter })), { reliable: true });

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

    if (tracks.length === 0) {
        return (
            <div className="absolute inset-0 flex flex-col justify-center items-center z-50 bg-gradient-to-br from-gray-900 to-black animate-pulse transition-all duration-1000" style={{ backdropFilter: "blur(12px)", WebkitBackdropFilter: "blur(12px)" }}>
                <h2 className="text-3xl font-extrabold tracking-widest text-transparent bg-clip-text bg-gradient-to-r from-gray-200 to-gray-500 drop-shadow-2xl" style={{ letterSpacing: "0.15em", fontWeight: 900 }}>Yayıncı bekleniyor...</h2>
                <p className="opacity-50 mt-4 font-medium tracking-wide text-sm">Lütfen ayrılmayın, açık arttırma birazdan başlayacak.</p>
            </div>
        );
    }

    const hostTrack = tracks[0];
    const guestTrack = tracks.length > 1 ? tracks[1] : null;

    return (
        <div className="flex flex-col md:flex-row w-full h-full bg-neutral-950 overflow-hidden relative">
            {/* VİDEO ALANI (Sol veya Üst) - FULL WIDTH & HEIGHT */}
            <div className="flex-[1_1_0] min-h-0 relative bg-black overflow-hidden border-b md:border-b-0 md:border-r border-white/10 shadow-[inner_0_0_100px_rgba(0,0,0,0.8)] flex flex-col">
                {isOwner && (
                    <button
                        onClick={() => handleEndBroadcast()}
                        className="absolute top-4 right-4 z-[300] bg-red-600/80 hover:bg-red-500 text-white font-black px-6 py-2.5 rounded-full shadow-[0_4px_20px_rgba(220,38,38,0.5)] active:scale-95 transition-all flex items-center gap-2 border border-red-400/50 backdrop-blur-md"
                    >
                        <span className="w-2.5 h-2.5 rounded-full bg-white animate-pulse"></span>
                        🔴 Yayını Bitir
                    </button>
                )}

                {/* Floating Reactions overlaying video */}
                {reactions.map((r) => (
                    <div
                        key={r.id}
                        className="animate-[floatUp_2.5s_ease-out_forwards]"
                        style={{
                            position: "absolute",
                            bottom: "20%",
                            left: `${r.left}%`,
                            fontSize: "2.5rem",
                            pointerEvents: "none",
                            zIndex: 300,
                        }}
                    >
                        {r.emoji}
                    </div>
                ))}

                <style>{`
                    @keyframes floatUp {
                        0% { transform: translateY(0) scale(1); opacity: 1; }
                        100% { transform: translateY(-250px) scale(1.5); opacity: 0; }
                    }
                `}</style>

                {/* INNER VIDEO WRAPPER - STRETCHES FULLY */}
                <div className="w-full h-full relative overflow-hidden bg-neutral-900 border-0">
                    <div style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }}>
                        {/* Broadcast Ended Overlay */}
                        {isBroadcastEnded ? (
                            <div style={{
                                position: "absolute", inset: 0, display: "flex", flexDirection: "column",
                                justifyContent: "center", alignItems: "center", background: "#000", zIndex: 10
                            }}>
                                <div style={{ fontSize: "40px", marginBottom: "16px" }}>📡</div>
                                <h2 style={{ color: "white", fontSize: "24px", fontWeight: "bold", margin: 0 }}>Yayın Sona Erdi</h2>
                                <p style={{ color: "rgba(255,255,255,0.6)", marginTop: "8px" }}>Yayıncı canlı yayını kapattı.</p>
                            </div>
                        ) : (
                            <>
                                {hostTrack?.publication?.isMuted ? (
                                    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", background: "#111" }}>
                                        <div style={{ fontSize: "40px", marginBottom: "16px" }}>📷</div>
                                        <div style={{ color: "rgba(255,255,255,0.5)", fontWeight: "bold" }}>Kamera Kapalı</div>
                                    </div>
                                ) : (
                                    <VideoTrack trackRef={hostTrack} style={{ width: "100%", height: "100%", objectFit: "contain" }} />
                                )}

                                {/* =============================================
                        AUCTION_SOLD — PERMANENT SATILDI OVERLAY
                        Covers the video; locks all bidding interaction.
                    ============================================= */}
                                {auctionResult && showSoldOverlay && (
                                    <div className="absolute inset-0 flex flex-col items-center justify-center z-[200] bg-black/70 backdrop-blur-md">
                                        <div className="flex flex-col items-center gap-6 px-8 py-12 rounded-3xl border border-yellow-400/40"
                                            style={{
                                                background: "linear-gradient(135deg, rgba(0,0,0,0.7) 0%, rgba(30,20,0,0.85) 100%)",
                                                boxShadow: "0 0 80px rgba(234,179,8,0.35), 0 0 20px rgba(0,0,0,0.8)",
                                            }}>
                                            {/* Sold badge */}
                                            <div className="flex flex-col items-center">
                                                <span className="text-8xl mb-2 drop-shadow-[0_0_25px_rgba(255,215,0,0.9)] animate-pulse">🏆</span>
                                                <h1
                                                    className="text-6xl md:text-7xl font-black tracking-widest animate-pulse"
                                                    style={{
                                                        background: "linear-gradient(90deg, #FFD700 0%, #FFA500 40%, #FFD700 80%, #FFA500 100%)",
                                                        backgroundSize: "200% auto",
                                                        WebkitBackgroundClip: "text",
                                                        WebkitTextFillColor: "transparent",
                                                        textShadow: "none",
                                                        filter: "drop-shadow(0 0 20px rgba(255,165,0,0.7))",
                                                        animation: "shine 2s linear infinite, pulse 2s ease-in-out infinite",
                                                    }}
                                                >
                                                    SATILDI!
                                                </h1>
                                            </div>

                                            {/* Winner info */}
                                            <div className="flex flex-col items-center gap-2 mt-2">
                                                <p className="text-white/70 text-sm font-semibold tracking-widest uppercase">Kazanan</p>
                                                <p className="text-white text-2xl md:text-3xl font-black">{auctionResult.winnerName}</p>
                                                <div
                                                    className="mt-2 px-6 py-2 rounded-2xl font-black text-3xl md:text-4xl"
                                                    style={{
                                                        background: "linear-gradient(135deg, #10b981 0%, #059669 100%)",
                                                        boxShadow: "0 0 30px rgba(16,185,129,0.5)",
                                                        color: "white",
                                                    }}
                                                >
                                                    {new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(auctionResult.price)}
                                                </div>
                                                <p className="text-white/50 text-sm text-center mt-1">
                                                    Bu ürün&nbsp;
                                                    <span className="text-white font-semibold">{auctionResult.winnerName}</span>
                                                    &nbsp;adlı kullanıcıya satılmıştır.
                                                </p>
                                                <div className="mt-8 flex flex-wrap justify-center gap-4">
                                                    <button
                                                        onClick={() => setShowSoldOverlay(false)}
                                                        className="px-8 py-3 rounded-full font-bold text-white border border-white/50 bg-white/15 hover:bg-white/30 active:scale-95 transition-all duration-200 backdrop-blur-sm text-base tracking-wide"
                                                    >
                                                        Sohbete Dön / Kapat
                                                    </button>

                                                    {isOwner && isQuickLive && (
                                                        <button
                                                            onClick={handleResetAuction}
                                                            disabled={loading}
                                                            className="px-8 py-3 rounded-full font-bold text-white border-2 border-green-500 bg-green-500 hover:bg-green-400 active:scale-95 transition-all duration-200 shadow-[0_0_20px_rgba(34,197,94,0.6)] text-base tracking-wide flex items-center gap-2 disabled:opacity-50"
                                                        >
                                                            <span>🔄</span> Yeni Ürüne Geç
                                                        </button>
                                                    )}
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                )}

                                {/* SALE FINALIZATION OVERLAY (transient 10s animation) */}
                                {showFinalization && (
                                    <div className="absolute inset-0 flex items-center justify-center z-[100] bg-black/80 backdrop-blur-sm pointer-events-none transition-all duration-500">
                                        <div className="flex flex-col items-center bg-gradient-to-tr from-yellow-600/20 to-yellow-400/20 px-8 py-10 rounded-3xl border border-yellow-500/50 shadow-[0_0_60px_rgba(234,179,8,0.3)] transform scale-100 animate-[pulse_2s_ease-in-out_infinite]">
                                            <span className="text-6xl mb-4 drop-shadow-[0_0_15px_rgba(255,255,255,0.8)]">🎉</span>
                                            <h2 className="text-4xl md:text-5xl font-black text-transparent bg-clip-text bg-gradient-to-r from-yellow-300 to-yellow-600 drop-shadow-md tracking-widest mb-2">SATILDI!</h2>
                                            <p className="text-xl md:text-2xl text-white font-semibold mb-4">Tebrikler {finalizedWinner}!</p>
                                            {finalizedAmount != null && (
                                                <p className="text-3xl md:text-4xl text-green-400 font-extrabold drop-shadow-[0_0_10px_rgba(74,222,128,0.5)]">
                                                    {new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(finalizedAmount)}
                                                </p>
                                            )}
                                        </div>
                                    </div>
                                )}
                            </>
                        )}

                        {/* Unified UI Controls - Active only when broadcast is alive */}
                        {!isBroadcastEnded && (
                            <>
                                {/* Top HUD (Mobile Style) */}
                                <div style={{
                                    position: "absolute",
                                    top: "20px",
                                    left: "16px",
                                    right: "16px",
                                    zIndex: 200,
                                    display: "flex",
                                    justifyContent: "space-between",
                                    alignItems: "flex-start",
                                    pointerEvents: "none"
                                }}>
                                    {/* Left Side: Avatar & Badges */}
                                    <div style={{ display: "flex", flexDirection: "column", gap: "8px", pointerEvents: "auto" }}>
                                        <div style={{
                                            display: "flex",
                                            alignItems: "center",
                                            background: "rgba(0,0,0,0.5)",
                                            backdropFilter: "blur(10px)",
                                            borderRadius: "100px",
                                            padding: "4px",
                                            paddingRight: "16px",
                                            border: "1px solid rgba(255,255,255,0.1)"
                                        }}>
                                            <div style={{ width: "36px", height: "36px", borderRadius: "50%", background: "#ef4444", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "16px", fontWeight: "bold", color: "white" }}>
                                                {adOwnerName.charAt(0).toUpperCase()}
                                            </div>
                                            <div style={{ marginLeft: "10px", display: "flex", flexDirection: "column" }}>
                                                <span style={{ color: "white", fontSize: "0.85rem", fontWeight: 800 }}>{adOwnerName}</span>
                                                <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                                                    <span style={{ color: "white", fontSize: "0.6rem", background: "#ef4444", padding: "2px 6px", borderRadius: "4px", fontWeight: 900 }}>TEQLİF CANLI</span>
                                                </div>
                                            </div>
                                        </div>

                                        <div style={{ display: "flex", alignItems: "center", gap: "6px", background: "rgba(0,0,0,0.4)", backdropFilter: "blur(10px)", padding: "4px 12px", borderRadius: "100px", width: "max-content", border: "1px solid rgba(255,255,255,0.1)" }}>
                                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                                            <span style={{ color: "white", fontSize: "0.8rem", fontWeight: 700 }}>{participantCount}</span>
                                        </div>
                                    </div>

                                    {/* Right Side: Close / Leave */}
                                    <div style={{ pointerEvents: "auto" }}>
                                        {isOwner ? (
                                            <button onClick={() => handleEndBroadcast()} style={{ background: "rgba(0,0,0,0.4)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "50%", width: "40px", height: "40px", display: "flex", alignItems: "center", justifyContent: "center", color: "white", cursor: "pointer", backdropFilter: "blur(10px)" }}>
                                                ✕
                                            </button>
                                        ) : (
                                            <button onClick={() => window.location.href = "/"} style={{ background: "rgba(0,0,0,0.4)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "50%", width: "40px", height: "40px", display: "flex", alignItems: "center", justifyContent: "center", color: "white", cursor: "pointer", backdropFilter: "blur(10px)" }}>
                                                ✕
                                            </button>
                                        )}
                                    </div>
                                </div>

                                {/* Top Dashboard: Mobile Parity Price & Bidding Info (Below HUD) */}
                                <div style={{
                                    position: "absolute",
                                    top: "100px",
                                    left: "16px",
                                    right: "16px",
                                    zIndex: 200,
                                    display: "flex",
                                    flexDirection: "column",
                                    gap: "8px",
                                    pointerEvents: "auto"
                                }}>
                                    {/* Stats Bar */}
                                    <div style={{
                                        background: "rgba(255, 255, 255, 0.7)",
                                        backdropFilter: "blur(15px)",
                                        borderRadius: "20px",
                                        border: "1px solid rgba(0, 180, 204, 0.2)",
                                        padding: "12px 16px",
                                        display: "flex",
                                        justifyContent: "space-between",
                                        alignItems: "center"
                                    }}>
                                        <div style={{ display: "flex", flexDirection: "column" }}>
                                            <span style={{ fontSize: "0.65rem", color: "rgba(0, 180, 204, 0.8)", fontWeight: 800, letterSpacing: "1px" }}>
                                                {auctionStatus === "ACTIVE" ? "GÜNCEL FİYAT" : "BAŞLANGIÇ FİYATI"}
                                            </span>
                                            <div style={{ display: "flex", alignItems: "baseline", gap: "4px" }}>
                                                <span className={`tabular-nums tracking-tighter ${flashBid ? 'text-primary scale-110' : 'text-[#00B4CC]'} transition-all duration-300`} style={{ fontSize: "1.5rem", fontWeight: 900 }}>
                                                    {new Intl.NumberFormat("tr-TR").format(liveHighestBid || (startingBid ?? 0))}
                                                </span>
                                                <span style={{ fontSize: "1rem", color: "var(--primary)", fontWeight: 700 }}>₺</span>
                                            </div>
                                        </div>

                                        <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
                                            {liveHighestBidderName ? (
                                                <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                                                    <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
                                                        <span style={{ fontSize: "0.6rem", color: "var(--text-secondary)", fontWeight: 800 }}>LİDER</span>
                                                        <span style={{ fontSize: "0.85rem", color: "var(--primary)", fontWeight: 900 }}>{liveHighestBidderName}</span>
                                                    </div>
                                                    {isOwner && liveHighestBidderId && (
                                                        <button
                                                            onClick={() => {
                                                                if (confirm(`${liveHighestBidderName} adlı kullanıcıyı sahneye davet etmek istiyor musunuz?`)) {
                                                                    const payload = JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: liveHighestBidderId });
                                                                    room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                                                                    alert("Davet gönderildi!");
                                                                }
                                                            }}
                                                            title="Sahneye Davet Et"
                                                            style={{ background: "rgba(0, 180, 204, 0.08)", border: "1px solid rgba(0, 180, 204, 0.2)", borderRadius: "8px", padding: "6px", cursor: "pointer", marginLeft: "4px" }}
                                                        >
                                                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
                                                        </button>
                                                    )}
                                                </div>
                                            ) : (
                                                <div style={{ display: "flex", alignItems: "center", gap: "4px" }}>
                                                    <span style={{ width: "8px", height: "8px", borderRadius: "50%", background: auctionStatus === "ACTIVE" ? "#22c55e" : "#f59e0b", animation: auctionStatus === "ACTIVE" ? "pulse 1.5s infinite" : "none" }} />
                                                    <span style={{ fontSize: "0.75rem", color: "white", fontWeight: 800 }}>{auctionStatus === "ACTIVE" ? "TEKLİF BEKLENİYOR" : "BAŞLAMASI BEKLENİYOR"}</span>
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    {/* Host Quick Action Bar under Stats */}
                                    {isOwner && auctionStatus === "ACTIVE" && liveHighestBidId && (
                                        <div style={{ display: "flex", gap: "8px" }}>
                                            <button onClick={handleAccept} style={{ flex: 1, background: "linear-gradient(135deg, #10b981 0%, #059669 100%)", color: "white", border: "none", borderRadius: "12px", padding: "10px", fontSize: "0.8rem", fontWeight: 900, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", boxShadow: "0 4px 15px rgba(16, 185, 129, 0.3)" }}>
                                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
                                                ONAYLA VE SAT
                                            </button>
                                            <button onClick={handleReject} style={{ flex: 1, background: "rgba(239, 68, 68, 0.15)", color: "#ef4444", border: "1px solid rgba(239, 68, 68, 0.3)", borderRadius: "12px", padding: "10px", fontSize: "0.8rem", fontWeight: 900, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: "6px" }}>
                                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
                                                REDDET
                                            </button>
                                        </div>
                                    )}
                                </div>

                                {/* Center Controls Side Bar (Host specific Actions) */}
                                {isOwner && (
                                    <div style={{
                                        position: "absolute",
                                        bottom: "20px",
                                        left: "50%",
                                        transform: "translateX(-50%)",
                                        zIndex: 200,
                                        display: "flex",
                                        flexDirection: "row",
                                        alignItems: "center",
                                        gap: "16px",
                                        background: "rgba(0,0,0,0.5)",
                                        backdropFilter: "blur(12px)",
                                        borderRadius: "100px",
                                        padding: "8px 24px",
                                        pointerEvents: "auto",
                                        border: "1px solid rgba(255,255,255,0.1)"
                                    }}>
                                        <TrackToggle
                                            source={Track.Source.Microphone}
                                            className="backdrop-blur-lg bg-black/40 hover:bg-black/60 transition-all shadow-lg"
                                            style={{
                                                border: "1px solid rgba(255,255,255,0.1)",
                                                borderRadius: "50%",
                                                width: "48px",
                                                height: "48px",
                                                color: "white",
                                                display: "flex",
                                                alignItems: "center",
                                                justifyContent: "center",
                                                cursor: "pointer"
                                            }}
                                        />
                                        <TrackToggle
                                            source={Track.Source.Camera}
                                            className="backdrop-blur-lg bg-black/40 hover:bg-black/60 transition-all shadow-lg"
                                            style={{
                                                border: "1px solid rgba(255,255,255,0.1)",
                                                borderRadius: "50%",
                                                width: "48px",
                                                height: "48px",
                                                color: "white",
                                                display: "flex",
                                                alignItems: "center",
                                                justifyContent: "center",
                                                cursor: "pointer"
                                            }}
                                        />
                                        <button
                                            onClick={async () => {
                                                try {
                                                    const publications = Array.from(room.localParticipant.videoTrackPublications.values());
                                                    const videoPub = publications.find(p => p.source === Track.Source.Camera);
                                                    if (videoPub?.videoTrack) {
                                                        // @ts-ignore
                                                        await videoPub.videoTrack.switchCamera();
                                                    }
                                                } catch (e) {
                                                    console.error("Kamera değiştirme hatası:", e);
                                                }
                                            }}
                                            style={{
                                                width: "48px",
                                                height: "48px",
                                                borderRadius: "50%",
                                                background: "rgba(0,0,0,0.4)",
                                                backdropFilter: "blur(12px)",
                                                border: "1px solid rgba(255,255,255,0.1)",
                                                fontSize: "20px",
                                                display: "flex",
                                                alignItems: "center",
                                                justifyContent: "center",
                                                color: "white",
                                                cursor: "pointer"
                                            }}
                                            title="Kamera Değiştir"
                                        >
                                            🔄
                                        </button>
                                        <button
                                            onClick={async () => {
                                                if (!confirm("Açık arttırmayı sıfırlamak istiyor musunuz? Tüm teklifler arşivlenecek ve başlangıç fiyatına dönülecektir.")) return;
                                                setLoading(true);
                                                try {
                                                    const res = await fetch(`/api/ads/${adId}/auction/reset`, { method: "POST" });
                                                    if (res.ok) {
                                                        const payload = JSON.stringify({ type: "AUCTION_RESET" });
                                                        room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                                                        setLiveHighestBid(initialHighestBid);
                                                        setLiveHighestBidId(null);
                                                        setLiveHighestBidderId(null);
                                                        setLiveHighestBidderName(null);
                                                        setAuctionStatus("ACTIVE");
                                                        alert("Açık arttırma sıfırlandı.");
                                                    }
                                                } catch (e) {
                                                    console.error(e);
                                                }
                                                setLoading(false);
                                            }}
                                            style={{
                                                width: "48px",
                                                height: "48px",
                                                borderRadius: "50%",
                                                background: "rgba(220, 38, 38, 0.8)",
                                                backdropFilter: "blur(12px)",
                                                border: "1px solid rgba(255,255,255,0.1)",
                                                fontSize: "20px",
                                                display: "flex",
                                                alignItems: "center",
                                                justifyContent: "center",
                                                color: "white",
                                                cursor: "pointer",
                                                boxShadow: "0 4px 15px rgba(220, 38, 38, 0.4)"
                                            }}
                                            title="Açık Arttırmayı Sıfırla"
                                        >
                                            🔄 0
                                        </button>
                                        {/* Stage Requests Pulse Icon */}
                                        {stageRequests.length > 0 && (
                                            <div style={{ position: "relative" }}>
                                                <button
                                                    onClick={() => {
                                                        const req = stageRequests[0];
                                                        if (confirm(`${req.name} adlı kullanıcıyı sahneye davet etmek istiyor musunuz?`)) {
                                                            const payload = JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: req.id });
                                                            room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                                                            setStageRequests(prev => prev.filter(r => r.id !== req.id));
                                                        } else {
                                                            setStageRequests(prev => prev.filter(r => r.id !== req.id));
                                                        }
                                                    }}
                                                    style={{
                                                        width: "48px", height: "48px", borderRadius: "50%",
                                                        background: "rgba(59, 130, 246, 0.8)", border: "2px solid rgba(255,255,255,0.5)",
                                                        display: "flex", alignItems: "center", justifyContent: "center", color: "white",
                                                        cursor: "pointer", boxShadow: "0 0 15px rgba(59, 130, 246, 0.8)", animation: "pulse 1.5s infinite"
                                                    }}
                                                >
                                                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2v20"></path><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg>
                                                </button>
                                                <span style={{ position: "absolute", top: "-5px", right: "-5px", background: "red", color: "white", fontSize: "10px", fontWeight: "bold", padding: "2px 6px", borderRadius: "10px" }}>{stageRequests.length}</span>
                                            </div>
                                        )}
                                    </div>
                                )}

                                {/* Flying Emojis */}
                                {reactions.map((reaction) => (
                                    <div key={reaction.id} className="floating-emoji" style={{ bottom: "80px", left: `${reaction.left}%`, fontSize: "32px", pointerEvents: "none" }}>
                                        {reaction.emoji}
                                    </div>
                                ))}

                                {/* Bottom Gradient for Chat & Console */}
                                <div style={{
                                    position: "absolute",
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    height: "40%",
                                    background: "linear-gradient(to top, rgba(0,0,0,0.8) 0%, rgba(0,0,0,0.4) 40%, transparent 100%)",
                                    pointerEvents: "none",
                                    zIndex: 100
                                }} />

                                {/* Huge Auction Status Notification Overlay */}
                                {auctionNotification && (
                                    <div style={{
                                        position: "absolute",
                                        inset: 0,
                                        display: "flex",
                                        alignItems: "center",
                                        justifyContent: "center",
                                        background: auctionNotification.includes("BAŞLADI") ? "rgba(34, 197, 94, 0.3)" : "rgba(249, 115, 22, 0.3)",
                                        backdropFilter: "blur(8px)",
                                        WebkitBackdropFilter: "blur(8px)",
                                        zIndex: 300,
                                        animation: "zoomFadeOut 4s ease-in-out forwards"
                                    }}>
                                        <div style={{
                                            background: auctionNotification.includes("BAŞLADI") ? "linear-gradient(135deg, #16a34a 0%, #22c55e 100%)" : "linear-gradient(135deg, #ea580c 0%, #f97316 100%)",
                                            color: "white",
                                            padding: "30px 60px",
                                            borderRadius: "30px",
                                            fontWeight: 900,
                                            fontSize: "2.5rem",
                                            letterSpacing: "2px",
                                            boxShadow: "0 20px 40px rgba(0,0,0,0.5)",
                                            border: "4px solid rgba(255,255,255,0.4)",
                                            textAlign: "center"
                                        }}>
                                            {auctionNotification}
                                        </div>
                                    </div>
                                )}

                                {/* Countdown Gamification Overlay */}
                                {countdown > 0 && (
                                    <div
                                        className={countdown <= 10 ? "animate-pulse" : ""}
                                        style={{
                                            position: "absolute",
                                            top: "35%",
                                            left: "50%",
                                            transform: "translate(-50%, -50%)",
                                            background: countdown <= 10 ? "rgba(239, 68, 68, 0.9)" : "rgba(245, 158, 11, 0.9)",
                                            color: "white",
                                            width: "120px",
                                            height: "120px",
                                            display: "flex",
                                            alignItems: "center",
                                            justifyContent: "center",
                                            borderRadius: "50%",
                                            fontWeight: 900,
                                            fontSize: "4rem",
                                            boxShadow: `0 0 50px ${countdown <= 10 ? 'rgba(239, 68, 68, 0.6)' : 'rgba(245, 158, 11, 0.6)'}`,
                                            zIndex: 150,
                                            animation: "zoomIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)"
                                        }}
                                    >
                                        {countdown}
                                    </div>
                                )}

                                {/* Guest PiP Screen */}
                                {guestTrack && (
                                    <div style={{
                                        position: "absolute",
                                        bottom: "100px",
                                        right: "20px",
                                        width: "100px",
                                        height: "140px",
                                        borderRadius: "12px",
                                        overflow: "hidden",
                                        border: "2px solid white",
                                        boxShadow: "0 8px 24px rgba(0,0,0,0.5)",
                                        zIndex: 10,
                                        background: "black"
                                    }}>
                                        {guestTrack?.publication?.isMuted ? (
                                            <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", flexDirection: "column", background: "#333" }}>
                                                <div style={{ fontSize: "24px" }}>📷</div>
                                            </div>
                                        ) : (
                                            <VideoTrack trackRef={guestTrack} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                                        )}
                                    </div>
                                )}

                            </>
                        )}
                    </div>
                </div>
            </div>

            {/* KONTROL PANELİ (Sağ veya Alt) - KESİNLİKLE GÖRÜNÜR OLMALI */}
            {!isBroadcastEnded && (
                <div className="w-full md:w-96 flex-shrink-0 flex flex-col bg-white/5 backdrop-blur-3xl relative z-50 h-[45vh] md:h-full p-4 pb-2">
                    {/* Chat Area & Reactions Tray */}
                    <div className="flex-[1_1_0] flex overflow-hidden pointer-events-auto mb-4" style={{ minHeight: "0" }}>
                        {/* SOHBET KUTUSU - BU KODU KESİNLİKLE Ekle */}
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

                        {/* Viewer Emojis and Stage Requests Panel */}
                        <div style={{ display: "flex", flexDirection: "column", gap: "10px", alignItems: "flex-end", justifySelf: "flex-end", paddingLeft: "8px" }}>
                            {['❤️', '👏', '🔥'].map(emoji => (
                                <button
                                    key={emoji}
                                    onClick={() => handleReaction(emoji)}
                                    className={`hover:scale-110 active:scale-90 transition-transform w-[45px] h-[45px] rounded-full bg-black/40 backdrop-blur-md border border-white/20 text-xl flex items-center justify-center cursor-pointer ${emoji === '❤️' ? 'mt-auto' : ''}`}
                                >
                                    {emoji}
                                </button>
                            ))}

                            {!isOwner && (
                                <>
                                    <button
                                        onClick={() => {
                                            if (confirm("Sahneye katılma isteği göndermek istiyor musunuz?")) {
                                                const payload = JSON.stringify({ type: "REQUEST_STAGE", userId: session?.user?.id, userName: session?.user?.name });
                                                room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                                                alert("İstek gönderildi!");
                                            }
                                        }}
                                        className="hover:scale-110 active:scale-90 transition-transform w-[45px] h-[45px] rounded-full bg-cyan-500/40 backdrop-blur-md border border-cyan-500/80 flex items-center justify-center cursor-pointer"
                                    >
                                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
                                    </button>

                                    <button
                                        onClick={() => {
                                            alert("Detaylar sayfanın altında yer almaktadır.");
                                            window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
                                        }}
                                        className="hover:scale-110 active:scale-90 transition-transform w-[45px] h-[45px] rounded-full bg-white/20 backdrop-blur-md border border-white/40 flex items-center justify-center cursor-pointer"
                                    >
                                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
                                    </button>
                                </>
                            )}
                        </div>
                    </div>

                    {/* Bottom Console (Chat Input & Action Button) */}
                    <div className="w-full pointer-events-auto flex flex-col gap-3 shrink-0">
                        {/* SOHBET INPUTU */}
                        <form
                            onSubmit={(e) => {
                                e.preventDefault();
                                if (message.trim()) {
                                    send(message);
                                    setMessage("");
                                }
                            }}
                            className="w-full min-h-[50px] flex items-center gap-2 bg-black/50 backdrop-blur-md border border-white/10 rounded-full px-4 pr-1"
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

                        {/* Primary Action Button (Host: Start/End, Viewer: Bid) */}
                        {isOwner ? (
                            <div className="w-full flex flex-col gap-2 mt-2">
                                {auctionStatus === "IDLE" ? (
                                    <button
                                        onClick={startCountdown}
                                        className="w-full flex items-center justify-center transition-all hover:scale-[1.02] active:scale-[0.98] min-h-[60px] px-6 text-white border-none rounded-2xl text-xl font-black shadow-[0_4px_25px_rgba(16,185,129,0.5)] bg-gradient-to-br from-emerald-500 to-emerald-700 uppercase tracking-widest"
                                    >
                                        Açık Artırmayı Başlat
                                    </button>
                                ) : (
                                    <>
                                        <button
                                            onClick={handleAccept}
                                            disabled={!liveHighestBidId || loading}
                                            className="w-full flex items-center justify-center transition-all active:scale-[0.98] min-h-[60px] px-6 text-white border border-emerald-400/50 rounded-2xl text-xl font-black shadow-[0_4px_25px_rgba(16,185,129,0.6)] bg-emerald-600 hover:bg-emerald-500 disabled:bg-emerald-900/50 disabled:opacity-50 disabled:cursor-not-allowed uppercase tracking-wider"
                                        >
                                            {loading ? "Satılıyor..." : "KABUL ET VE SAT"}
                                        </button>
                                        <div className="flex gap-2">
                                            <button
                                                onClick={handleStopAuction}
                                                className="flex-[1] flex items-center justify-center transition-all active:scale-95 min-h-[44px] px-4 text-white border border-orange-500/50 rounded-xl text-sm font-bold shadow-lg bg-orange-600/80 hover:bg-orange-500 uppercase"
                                            >
                                                Durdur
                                            </button>
                                            {isQuickLive && (
                                                <button
                                                    onClick={handleResetAuction}
                                                    className="flex-[1] flex items-center justify-center transition-all active:scale-95 min-h-[44px] px-4 text-white border border-blue-500/50 rounded-xl text-sm font-bold shadow-lg bg-blue-600/80 hover:bg-blue-500 uppercase"
                                                >
                                                    Sıfırla
                                                </button>
                                            )}
                                        </div>
                                    </>
                                )}
                            </div>
                        ) : (
                            // Viewer Bidding or Sold Status
                            <div className="w-full mt-2">
                                {auctionResult ? (
                                    <div className="h-[50px] px-6 bg-emerald-500/20 backdrop-blur-md border border-emerald-500/40 rounded-2xl text-emerald-500 font-black flex items-center justify-center">
                                        BU ÜRÜN SATILMIŞTIR
                                    </div>
                                ) : auctionStatus === "ACTIVE" ? (
                                    <BidMiniForm adId={adId} currentHighest={liveHighestBid} minStep={minBidStep} startingBid={startingBid} />
                                ) : (
                                    <div className="h-[50px] px-6 bg-white/10 backdrop-blur-md border border-white/20 rounded-2xl text-white/50 font-black flex items-center justify-center">
                                        BEKLENİYOR
                                    </div>
                                )}
                            </div>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
}

// Mini bid form for consolidated dashboard
function BidMiniForm({ adId, currentHighest, minStep, startingBid }: any) {
    const router = useRouter();
    const [amount, setAmount] = useState("");
    const [loading, setLoading] = useState(false);
    const { data: session } = useSession();

    const handleQuickBid = async (val: number) => {
        if (!session?.user?.id) return;
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/bid", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ roomId: adId, amount: (currentHighest || startingBid || 0) + val }),
            });
            const data = await res.json();
            if (!res.ok) alert(data.error || data.message || "Teklif verilemedi.");
            else router.refresh();
        } catch (e) { console.error(e); alert("Bir hata oluştu."); }
        setLoading(false);
    };

    const handleCustomBid = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount || !session?.user?.id) return;
        const rawAmount = parseInt(amount.replace(/\./g, ""), 10);
        if (rawAmount <= (currentHighest || 0)) {
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
            if (res.ok) { setAmount(""); router.refresh(); }
            else { const d = await res.json(); alert(d.error || d.message || "Hata"); }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    };

    return (
        <form onSubmit={handleCustomBid} className="flex flex-col w-full bg-black/40 border border-white/5 rounded-2xl p-4 gap-4 backdrop-blur-xl shadow-2xl">
            {/* The Climax Number */}
            <div className="flex flex-col items-center justify-center">
                <span className="text-xs font-bold text-white/50 tracking-widest uppercase mb-1 drop-shadow-md">GÜNCEL FİYAT</span>
                <span
                    className="text-5xl font-black tabular-nums tracking-tighter text-emerald-400 mb-2"
                    style={{ textShadow: "0 0 20px rgba(52, 211, 153, 0.4)" }}
                >
                    {new Intl.NumberFormat("tr-TR").format(currentHighest || (startingBid ?? 0))}
                </span>
            </div>

            {/* Quick Bids */}
            <div className="flex flex-row justify-center gap-2 w-full">
                {[50, 100, 500].map(val => (
                    <button
                        key={val}
                        type="button"
                        disabled={loading}
                        onClick={() => handleQuickBid(val)}
                        className="flex-1 py-2 rounded-full bg-white/10 hover:bg-white/20 active:scale-95 border border-white/20 text-white font-bold text-sm transition-all shadow-lg backdrop-blur-md disabled:opacity-50"
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
                    className="flex-[2] min-w-0 h-[50px] bg-white/10 backdrop-blur-md border border-white/20 focus:border-emerald-500 rounded-2xl px-4 text-white text-lg text-center font-black outline-none placeholder-white/30 transition-all"
                    placeholder="Özel teklif"
                />
                <button
                    type="submit"
                    disabled={loading || !amount}
                    className="flex-[1] h-[50px] bg-emerald-600 hover:bg-emerald-500 disabled:bg-emerald-800 disabled:opacity-50 text-white border-0 rounded-2xl font-black tracking-wide transition-all shadow-lg active:scale-95"
                >
                    {loading ? "..." : "TEKLİF VER"}
                </button>
            </div>
        </form>
    );
}

function CoHostListener({ setRole, setWantsToPublish }: { setRole: any, setWantsToPublish: any }) {

    const [inviteVisible, setInviteVisible] = useState(false);
    const room = useRoomContext();
    const { chatMessages, send: sendChat } = useChat();

    useDataChannel((msg) => {
        try {
            const dataStr = new TextDecoder().decode(msg.payload);
            const dataObj = JSON.parse(dataStr);

            if (dataObj.type === "INVITE_TO_STAGE") {
                setInviteVisible(true);
            } else if (dataObj.type === "KICK_FROM_STAGE") {
                setWantsToPublish(false);
                setRole("viewer");
                alert("Sahneden alındınız.");
                room.disconnect();
            }
        } catch (e) {
            // console.error("Data channel parse error", e);
        }
    });

    if (!inviteVisible) return null;

    return (
        <div style={{
            position: "absolute",
            top: 0, left: 0, right: 0, bottom: 0,
            background: "rgba(0,0,0,0.8)",
            backdropFilter: "blur(12px)",
            WebkitBackdropFilter: "blur(12px)",
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            zIndex: 9999,
        }}>
            <div style={{
                background: "rgba(255, 255, 255, 0.05)",
                padding: "32px",
                borderRadius: "24px",
                maxWidth: "340px",
                textAlign: "center",
                border: "1px solid rgba(255, 255, 255, 0.2)",
                boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.7)",
                animation: "fadeInUp 0.4s ease-out forwards"
            }}>
                <div style={{ fontSize: "3rem", marginBottom: "16px" }}>🎤</div>
                <h3 style={{ marginTop: 0, color: "white", fontSize: "1.5rem", fontWeight: 900 }}>Sahneye Davet!</h3>
                <p style={{ fontSize: "0.95rem", color: "rgba(255,255,255,0.7)", lineHeight: 1.5 }}>
                    Yayıncı sizinle beraber yayına katılmanızı istiyor. <b>Kameranız açılacaktır.</b> Kabul ediyor musunuz?
                </p>
                <div style={{ display: "flex", gap: "12px", justifyContent: "center", marginTop: "24px" }}>
                    <button
                        onClick={() => setInviteVisible(false)}
                        style={{
                            background: "rgba(255, 255, 255, 0.1)",
                            color: "white",
                            border: "1px solid rgba(255, 255, 255, 0.2)",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontSize: "0.9rem",
                            fontWeight: 700,
                            cursor: "pointer",
                            transition: "all 0.2s"
                        }}
                        onMouseOver={e => e.currentTarget.style.background = "rgba(255, 255, 255, 0.2)"}
                        onMouseOut={e => e.currentTarget.style.background = "rgba(255, 255, 255, 0.1)"}
                    >
                        Reddet
                    </button>
                    <button
                        onClick={async () => {
                            setInviteVisible(false);
                            await room.disconnect();
                            setRole("guest");
                        }}
                        style={{
                            background: "linear-gradient(135deg, #00B4CC, #008da1)",
                            color: "white",
                            border: "none",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontSize: "0.9rem",
                            fontWeight: 800,
                            cursor: "pointer",
                            boxShadow: "0 8px 20px rgba(0, 180, 204, 0.4)",
                            transition: "all 0.2s"
                        }}
                    >
                        Kabul Et
                    </button>
                </div>
            </div>
        </div>
    );
}

// New BidForm component for viewers
function BidForm({ adId, currentHighest, minStep, startingBid, formattedPrice }: any) {
    const router = useRouter();
    const [amount, setAmount] = useState("");
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState<any>(null);

    useEffect(() => {
        const nextMin = currentHighest > 0 ? (currentHighest + minStep) : (startingBid ?? 1);
        setAmount(new Intl.NumberFormat("tr-TR").format(nextMin));
    }, [currentHighest, minStep, startingBid]);

    useEffect(() => {
        if (status) {
            const timer = setTimeout(() => setStatus(null), 4000);
            return () => clearTimeout(timer);
        }
    }, [status]);

    async function handleBid(e: React.FormEvent) {
        e.preventDefault();
        setLoading(true);
        setStatus(null);

        const rawAmount = parseInt(amount.replace(/\./g, ""), 10);
        const minReq = currentHighest > 0 ? (currentHighest + minStep) : (startingBid ?? 1);

        if (!rawAmount || rawAmount < minReq) {
            setStatus({ type: 'error', msg: `Min: ${formattedPrice(minReq)}` });
            setLoading(false);
            return;
        }

        try {
            const res = await fetch("/api/bids", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId, amount: rawAmount }),
            });
            const data = await res.json();
            if (res.ok) {
                setStatus({ type: 'success', msg: 'teqlif verildi!' });
                router.refresh();
            } else {
                setStatus({ type: 'error', msg: data.error || 'Hata' });
            }
        } catch (e) {
            setStatus({ type: 'error', msg: 'Bağlantı hatası' });
        } finally {
            setLoading(false);
        }
    }

    return (
        <form onSubmit={handleBid} style={{
            background: "rgba(0,0,0,0.6)",
            backdropFilter: "blur(10px)",
            border: "1px solid rgba(255,255,255,0.1)",
            borderRadius: "1rem",
            padding: "1.5rem",
            display: "flex",
            flexDirection: "column",
            gap: "1rem",
            color: "white",
            position: "relative"
        }}>
            <h3 style={{ margin: 0, fontSize: "1.2rem", fontWeight: "bold", textAlign: "center" }}>teqlif Ver</h3>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "0.5rem" }}>
                <span style={{ fontSize: "0.8rem", opacity: 0.7 }}>Güncel:</span>
                <span style={{ fontSize: "1.2rem", fontWeight: 800, color: "#22c55e" }}>{formattedPrice(currentHighest || (startingBid ?? 0))}</span>
            </div>
            <input
                type="text"
                value={amount}
                onChange={(e) => {
                    const val = e.target.value.replace(/[^0-9]/g, "");
                    setAmount(val ? new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)) : "");
                }}
                placeholder="Miktar"
                style={{
                    width: "100%",
                    padding: "12px 16px",
                    background: "rgba(255, 255, 255, 0.1)",
                    border: "1px solid rgba(255, 255, 255, 0.2)",
                    borderRadius: "0.75rem",
                    color: "white",
                    fontSize: "1rem",
                    textAlign: "center",
                    outline: "none"
                }}
            />
            <button
                type="submit"
                disabled={loading}
                style={{
                    width: "100%",
                    background: "var(--primary)",
                    color: "white",
                    border: "none",
                    borderRadius: "0.75rem",
                    padding: "12px",
                    fontSize: "1rem",
                    fontWeight: 700,
                    cursor: "pointer",
                    transition: "all 0.2s",
                    boxShadow: "0 4px 15px rgba(0, 188, 212, 0.4)"
                }}
            >
                {loading ? "..." : "teqlif ver"}
            </button>
            {status && (
                <div style={{
                    position: "absolute",
                    top: "-35px",
                    left: "50%",
                    transform: "translateX(-50%)",
                    whiteSpace: "nowrap",
                    background: status.type === 'success' ? "rgba(34, 197, 94, 0.9)" : "rgba(239, 68, 68, 0.9)",
                    padding: "4px 12px",
                    borderRadius: "10px",
                    fontSize: "0.75rem",
                    fontWeight: 700
                }}>
                    {status.msg}
                </div>
            )}
        </form>
    );
}
