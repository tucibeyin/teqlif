"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer, useTracks, VideoTrack, useDataChannel, useRoomContext, TrackToggle, useConnectionState, useParticipants } from "@livekit/components-react";
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
    adOwnerName = "Satıcı"
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
            className="w-full bg-black relative rounded-xl overflow-hidden shadow-2xl"
            style={{ height: "calc(100vh - 120px)", minHeight: "500px", maxHeight: "800px" }}
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
    adOwnerName
}: any) {
    const room = useRoomContext();
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

    // Finalization overlay state
    const [finalizedWinner, setFinalizedWinner] = useState<string | null>(null);
    const [finalizedAmount, setFinalizedAmount] = useState<number | null>(null);
    const [showFinalization, setShowFinalization] = useState(false);

    // Countdown Gamification
    const [countdown, setCountdown] = useState(0);

    // Reactions State
    const [reactions, setReactions] = useState<{ id: string, emoji: string, left: number }[]>([]);
    // Bidding & Interaction State
    const [chatText, setChatText] = useState("");
    const [lastReactionTime, setLastReactionTime] = useState(0);
    const [loading, setLoading] = useState(false);

    const formattedPrice = (val: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

    const handleAccept = async () => {
        if (!liveHighestBidId) return;
        if (!confirm("Dikkat! Bu teqlifi kabul edip satışı tamamlıyorsunuz?")) return;
        setLoading(true);
        try {
            const resAccept = await fetch(`/api/bids/${liveHighestBidId}/accept`, { method: "PATCH" });
            if (resAccept.ok) {
                const resFinalize = await fetch(`/api/bids/${liveHighestBidId}/finalize`, { method: "POST" });
                if (resFinalize.ok) {
                    alert("Satış tamamlandı!");
                    // await handleEndBroadcast(true); // Removed: Keep stream open

                    // Signal auction end and sale finalized
                    if (room) {
                        const payloadEnd = JSON.stringify({ type: "AUCTION_END" });
                        room.localParticipant.publishData(new TextEncoder().encode(payloadEnd), { reliable: true });

                        const payloadFinalized = JSON.stringify({
                            type: "SALE_FINALIZED",
                            winnerName: liveHighestBidderId, // Optionally pass actual name if available
                            amount: liveHighestBid
                        });
                        room.localParticipant.publishData(new TextEncoder().encode(payloadFinalized), { reliable: true });
                    }
                    setCountdown(0);
                }
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    };

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

    const handleSendChat = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!chatText.trim() || !room) return;
        const payload = JSON.stringify({
            type: "CHAT",
            text: chatText.trim(),
            senderName: session?.user?.name || "Web Katılımcı",
            senderId: session?.user?.id
        });
        try {
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            const newMessage = { id: Date.now().toString(), text: chatText.trim(), sender: session?.user?.name || "Ben" };
            setMessages(prev => [...prev.slice(-10), newMessage]);
            setTimeout(() => setMessages(prev => prev.filter(m => m.id !== newMessage.id)), 8000);
            setChatText("");
        } catch (e) { console.error(e); }
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

    const handleStartAuction = async () => {
        if (!room) return;
        setLoading(true);
        try {
            const payload = JSON.stringify({ type: "AUCTION_START" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("ACTIVE");
            setAuctionNotification("📣 AÇIK ARTTIRMA BAŞLADI!");
            setTimeout(() => setAuctionNotification(null), 4000);
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    };

    const handleStopAuction = async () => {
        if (!room) return;
        setLoading(true);
        try {
            const payload = JSON.stringify({ type: "AUCTION_END" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("IDLE");
            setAuctionNotification("📣 AÇIK ARTTIRMA DURDURULDU");
            setTimeout(() => setAuctionNotification(null), 4000);
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    };

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
            } else if (dataObj.type === 'SYNC_STATE_RESPONSE') {
                if (dataObj.auctionStatus) setAuctionStatus(dataObj.auctionStatus);
                if (dataObj.liveHighestBid) setLiveHighestBid(dataObj.liveHighestBid);
                if (dataObj.liveHighestBidderName) setLiveHighestBidderName(dataObj.liveHighestBidderName);
            } else if (dataObj.type === 'CHAT') {
                const newMessage = {
                    id: Date.now().toString() + Math.random(),
                    text: dataObj.text,
                    sender: dataObj.senderName || "Katılımcı",
                    senderId: dataObj.senderId
                };
                setMessages(prev => [...prev.slice(-10), newMessage]); // Keep more messages
                setTimeout(() => {
                    setMessages(prev => prev.filter((m: any) => m.id !== newMessage.id));
                }, 8000); // Show longer
            } else if (dataObj.type === 'REACTION') {
                addReaction(dataObj.emoji);
            } else if (dataObj.type === 'AUCTION_START') {
                setAuctionStatus("ACTIVE");
                setAuctionNotification("📣 AÇIK ARTTIRMA BAŞLADI!");
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
            }
        }, 1000);
    }, [room]);

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
        <div style={{ position: "relative", width: "100%", height: "100%", background: "black" }}>
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
                    <VideoTrack trackRef={hostTrack} style={{ width: "100%", height: "100%", objectFit: "contain" }} />

                    {/* SALE FINALIZATION OVERLAY */}
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
                            background: "rgba(0,0,0,0.4)",
                            backdropFilter: "blur(15px)",
                            borderRadius: "20px",
                            border: "1px solid rgba(255,255,255,0.1)",
                            padding: "12px 16px",
                            display: "flex",
                            justifyContent: "space-between",
                            alignItems: "center"
                        }}>
                            <div style={{ display: "flex", flexDirection: "column" }}>
                                <span style={{ fontSize: "0.65rem", color: "rgba(255,255,255,0.6)", fontWeight: 800, letterSpacing: "1px" }}>
                                    {auctionStatus === "ACTIVE" ? "GÜNCEL FİYAT" : "BAŞLANGIÇ FİYATI"}
                                </span>
                                <div style={{ display: "flex", alignItems: "baseline", gap: "4px" }}>
                                    <span className={`tabular-nums tracking-tighter ${flashBid ? 'text-green-400 scale-110' : 'text-white'} transition-all duration-300`} style={{ fontSize: "1.5rem", fontWeight: 900 }}>
                                        {new Intl.NumberFormat("tr-TR").format(liveHighestBid || (startingBid ?? 0))}
                                    </span>
                                    <span style={{ fontSize: "1rem", color: "rgba(255,255,255,0.8)", fontWeight: 700 }}>₺</span>
                                </div>
                            </div>

                            <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
                                {liveHighestBidderName ? (
                                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                                        <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
                                            <span style={{ fontSize: "0.6rem", color: "rgba(255,255,255,0.6)", fontWeight: 800 }}>LİDER</span>
                                            <span style={{ fontSize: "0.85rem", color: "#4ade80", fontWeight: 900 }}>{liveHighestBidderName}</span>
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
                                                style={{ background: "rgba(59, 130, 246, 0.2)", border: "1px solid rgba(59, 130, 246, 0.5)", borderRadius: "8px", padding: "6px", cursor: "pointer", marginLeft: "4px" }}
                                            >
                                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#60a5fa" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
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
                        {isOwner && auctionStatus === "ACTIVE" && (
                            <div style={{ display: "flex", gap: "8px" }}>
                                <button onClick={handleAccept} style={{ flex: 1, background: "linear-gradient(135deg, #10b981 0%, #059669 100%)", color: "white", border: "none", borderRadius: "12px", padding: "10px", fontSize: "0.8rem", fontWeight: 900, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", boxShadow: "0 4px 15px rgba(16, 185, 129, 0.3)" }}>
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
                                    ONAYLA VE SAT
                                </button>
                            </div>
                        )}
                    </div>

                    {/* Center Controls Side Bar (Host specific Actions) */}
                    {isOwner && (
                        <div style={{
                            position: "absolute",
                            right: "16px",
                            bottom: "280px", // Just above the bottom console
                            zIndex: 200,
                            display: "flex",
                            flexDirection: "column",
                            gap: "12px",
                            pointerEvents: "auto"
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
                            <VideoTrack trackRef={guestTrack} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                        </div>
                    )}

                    {/* Bottom Interaction Area (Matches Mobile Console) */}
                    <div style={{
                        position: "absolute",
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: "260px",
                        display: "flex",
                        flexDirection: "column",
                        padding: "16px",
                        zIndex: 200,
                        pointerEvents: "none"
                    }}>
                        {/* Chat Area & Reactions Tray (Flex row so chat takes left, emojis take right) */}
                        <div style={{ flex: 1, display: "flex", overflow: "hidden", pointerEvents: "auto", marginBottom: "8px" }}>
                            <div style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: "6px", paddingRight: "10px" }}>
                                {messages.map((msg: any) => (
                                    <div key={msg.id} style={{
                                        background: "rgba(0,0,0,0.4)",
                                        backdropFilter: "blur(6px)",
                                        padding: "6px 14px",
                                        borderRadius: "16px",
                                        maxWidth: "85%",
                                        fontSize: "0.85rem",
                                        animation: "slideUp 0.3s ease-out",
                                        border: "1px solid rgba(255,255,255,0.05)",
                                        width: "max-content"
                                    }}>
                                        <span style={{ color: "#4ade80", fontWeight: 900, marginRight: "8px" }}>{msg.sender}:</span>
                                        <span style={{ color: "white" }}>{msg.text}</span>
                                    </div>
                                ))}
                            </div>

                            {/* Viewer Emojis and Stage Requests Panel */}
                            <div style={{ display: "flex", flexDirection: "column", gap: "10px", alignItems: "flex-end", justifyContent: "flex-end" }}>
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
                                            className="hover:scale-110 active:scale-90 transition-transform"
                                            style={{ width: "45px", height: "45px", borderRadius: "50%", background: "rgba(0,180,204,0.4)", backdropFilter: "blur(12px)", border: "1px solid rgba(0,180,204,0.8)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}
                                        >
                                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
                                        </button>

                                        <button
                                            onClick={() => {
                                                alert("Detaylar sayfanın altında yer almaktadır.");
                                                window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
                                            }}
                                            className="hover:scale-110 active:scale-90 transition-transform"
                                            style={{ width: "45px", height: "45px", borderRadius: "50%", background: "rgba(255,255,255,0.2)", backdropFilter: "blur(12px)", border: "1px solid rgba(255,255,255,0.4)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}
                                        >
                                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
                                        </button>
                                    </>
                                )}
                                {['❤️', '👏', '🔥'].map(emoji => (
                                    <button
                                        key={emoji}
                                        onClick={() => handleReaction(emoji)}
                                        className="hover:scale-110 active:scale-90 transition-transform"
                                        style={{ width: "45px", height: "45px", borderRadius: "50%", background: "rgba(0,0,0,0.4)", backdropFilter: "blur(12px)", border: "1px solid rgba(255,255,255,0.2)", fontSize: "20px", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}
                                    >
                                        {emoji}
                                    </button>
                                ))}
                            </div>
                        </div>

                        {/* Bottom Console (Chat Input & Action Button) */}
                        <div style={{ pointerEvents: "auto", display: "flex", gap: "10px", alignItems: "center" }}>
                            <form onSubmit={handleSendChat} style={{
                                flex: 1,
                                display: "flex",
                                gap: "8px",
                                background: "rgba(0,0,0,0.5)",
                                backdropFilter: "blur(10px)",
                                border: "1px solid rgba(255,255,255,0.1)",
                                borderRadius: "100px",
                                padding: "6px 8px 6px 16px",
                                height: "50px"
                            }}>
                                <input
                                    type="text"
                                    value={chatText}
                                    onChange={(e) => setChatText(e.target.value)}
                                    placeholder="Sohbet et..."
                                    style={{ background: "transparent", border: "none", outline: "none", color: "white", flex: 1, fontSize: "0.95rem" }}
                                />
                                <button type="submit" style={{ background: "#4ade80", color: "black", border: "none", borderRadius: "100px", width: "38px", height: "38px", fontWeight: "bold", display: "flex", alignItems: "center", justifyContent: "center" }}>
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
                                </button>
                            </form>

                            {/* Primary Action Button (Host: Start/End, Viewer: Bid) */}
                            {isOwner ? (
                                <button
                                    onClick={auctionStatus === "IDLE" ? startCountdown : () => handleEndBroadcast()}
                                    style={{
                                        height: "50px",
                                        padding: "0 24px",
                                        background: auctionStatus === "IDLE" ? "linear-gradient(135deg, #10b981 0%, #059669 100%)" : "linear-gradient(135deg, #ef4444 0%, #dc2626 100%)",
                                        color: "white", border: "none", borderRadius: "100px", fontWeight: 900,
                                        display: "flex", alignItems: "center", gap: "8px", cursor: "pointer",
                                        boxShadow: auctionStatus === "IDLE" ? "0 4px 15px rgba(16, 185, 129, 0.4)" : "0 4px 15px rgba(239, 68, 68, 0.4)"
                                    }}
                                >
                                    {auctionStatus === "IDLE" ? "BAŞLAT" : "BİTİR"}
                                </button>
                            ) : (
                                // Use the customized BidMiniForm which acts as a primary button for viewers
                                <div style={{ display: "flex", alignItems: "center" }}>
                                    {auctionStatus === "ACTIVE" ? (
                                        <BidMiniForm adId={adId} currentHighest={liveHighestBid} minStep={minBidStep} startingBid={startingBid} />
                                    ) : (
                                        <div style={{ height: "50px", padding: "0 24px", background: "rgba(255,255,255,0.1)", backdropFilter: "blur(10px)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "100px", color: "rgba(255,255,255,0.5)", fontWeight: 900, display: "flex", alignItems: "center", justifyContent: "center" }}>
                                            BEKLENİYOR
                                        </div>
                                    )}
                                </div>
                            )}
                        </div>
                    </div>
                </>
            )}
        </div>
    );
}

// Mini bid form for consolidated dashboard
function BidMiniForm({ adId, currentHighest, minStep, startingBid }: any) {
    const router = useRouter();
    const [amount, setAmount] = useState("");
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        const nextMin = currentHighest > 0 ? (currentHighest + minStep) : (startingBid ?? 1);
        setAmount(new Intl.NumberFormat("tr-TR").format(nextMin));
    }, [currentHighest, minStep, startingBid]);

    const handleBid = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        const rawAmount = parseInt(amount.replace(/\./g, ""), 10);
        try {
            const res = await fetch("/api/bids", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId, amount: rawAmount }),
            });
            if (res.ok) router.refresh();
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    };

    return (
        <form onSubmit={handleBid} style={{ display: "flex", gap: "8px", alignItems: "center" }}>
            <input
                type="text"
                value={amount}
                onChange={(e) => {
                    const val = e.target.value.replace(/[^0-9]/g, "");
                    setAmount(val ? new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)) : "");
                }}
                style={{
                    width: "110px",
                    height: "50px", // Increased height for bottom console parity
                    background: "rgba(0,0,0,0.5)",
                    backdropFilter: "blur(10px)",
                    border: "1px solid rgba(255,255,255,0.1)",
                    borderRadius: "100px",
                    padding: "0 16px",
                    color: "white",
                    fontSize: "0.95rem",
                    textAlign: "center",
                    fontWeight: 800,
                    outline: "none"
                }}
            />
            <button
                type="submit"
                disabled={loading}
                style={{
                    height: "50px",
                    background: "linear-gradient(135deg, #ef4444 0%, #b91c1c 100%)",
                    color: "white",
                    border: "none",
                    borderRadius: "100px",
                    padding: "0 20px",
                    fontSize: "0.9rem",
                    fontWeight: 900,
                    cursor: loading ? "not-allowed" : "pointer",
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                    boxShadow: "0 4px 15px rgba(239, 68, 68, 0.4)",
                    opacity: loading ? 0.7 : 1
                }}
            >
                {loading ? "BEKLEYİN" : "TEKLİF VER"}
                {!loading && <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M14 9l6 6-6 6"></path><path d="M4 4v7a4 4 0 0 0 4 4h11"></path></svg>}
            </button>
        </form>
    );
}

function CoHostListener({ setRole, setWantsToPublish }: { setRole: any, setWantsToPublish: any }) {

    const [inviteVisible, setInviteVisible] = useState(false);
    const room = useRoomContext();

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
                setStatus({ type: 'success', msg: 'Teqlif verildi!' });
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
            <h3 style={{ margin: 0, fontSize: "1.2rem", fontWeight: "bold", textAlign: "center" }}>Teqlif Ver</h3>
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
