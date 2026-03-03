"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer, useTracks, VideoTrack, useDataChannel, useRoomContext, TrackToggle, useConnectionState } from "@livekit/components-react";
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
}

export default function LiveArena({
    roomId,
    adId,
    sellerId,
    isOwner,
    buyItNowPrice,
    startingBid,
    minBidStep = 1,
    initialHighestBid = 0
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
                role={role}
                wantsToPublish={wantsToPublish}
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
    role,
    wantsToPublish
}: any) {
    const room = useRoomContext();
    const router = useRouter();
    const { data: session } = useSession();
    const tracks = useTracks([Track.Source.Camera]);
    const [liveHighestBid, setLiveHighestBid] = useState(initialHighestBid);
    const [lastAcceptedBidId, setLastAcceptedBidId] = useState<string | null>(null);
    const [liveHighestBidId, setLiveHighestBidId] = useState<string | null>(null);
    const [auctionStatus, setAuctionStatus] = useState<"IDLE" | "ACTIVE">("IDLE");
    const [auctionNotification, setAuctionNotification] = useState<string | null>(null);
    const [messages, setMessages] = useState<{ id: string, text: string, sender: string, senderId?: string }[]>([]);
    const [liveHighestBidderId, setLiveHighestBidderId] = useState<string | null>(null);
    const connectionState = useConnectionState();
    const [isRoomClosed, setIsRoomClosed] = useState(false);
    const [flashBid, setFlashBid] = useState(false);

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

                    // Signal auction end
                    if (room) {
                        const payload = JSON.stringify({ type: "AUCTION_END" });
                        await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
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
                setLastAcceptedBidId(null);
                setFlashBid(true);
                setTimeout(() => setFlashBid(false), 300);
            } else if (dataObj.type === 'BID_ACCEPTED') {
                setLiveHighestBid(dataObj.amount);
                setLiveHighestBidId(dataObj.bidId);
                setLiveHighestBidderId(dataObj.bidderId);
                setLastAcceptedBidId(dataObj.bidId);
                setFlashBid(true);
                setTimeout(() => setFlashBid(false), 300);
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
                room.disconnect();
            } else if (dataObj.type === 'COUNTDOWN') {
                setCountdown(dataObj.value);
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
                <VideoTrack trackRef={hostTrack} style={{ width: "100%", height: "100%", objectFit: "contain" }} />
            )}

            {/* Host Specific LiveKit Tools (Mic/Cam Toggle) */}
            {isOwner && (
                <div style={{
                    position: "absolute",
                    top: "20px",
                    left: "20px",
                    display: "flex",
                    gap: "10px",
                    zIndex: 50
                }}>
                    <TrackToggle
                        source={Track.Source.Microphone}
                        className="backdrop-blur-lg bg-white/10 hover:bg-white/20 transition-all shadow-lg"
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
                        className="backdrop-blur-lg bg-white/10 hover:bg-white/20 transition-all shadow-lg"
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
                </div>
            )}

            {/* Flying Emojis */}
            {reactions.map((reaction) => (
                <div key={reaction.id} className="floating-emoji" style={{ bottom: "80px", left: `${reaction.left}%`, fontSize: "32px", pointerEvents: "none" }}>
                    {reaction.emoji}
                </div>
            ))}

            {/* Reaction Buttons */}
            {!isBroadcastEnded && (
                <div style={{
                    position: "absolute",
                    bottom: isOwner ? "100px" : "440px",
                    right: "20px",
                    display: "flex",
                    flexDirection: "column",
                    gap: "12px",
                    zIndex: 150
                }}>
                    {/* Guest Controls (Mic/Cam) when on Stage */}
                    {!isOwner && role === "guest" && (
                        <div style={{ display: "flex", flexDirection: "column", gap: "10px", marginBottom: "10px" }}>
                            <TrackToggle
                                source={Track.Source.Microphone}
                                className="backdrop-blur-lg bg-white/10 hover:bg-white/20 transition-all shadow-lg"
                                style={{
                                    border: "1px solid rgba(255,255,255,0.1)",
                                    borderRadius: "50%",
                                    width: "45px",
                                    height: "45px",
                                    color: "white",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    cursor: "pointer"
                                }}
                            />
                            <TrackToggle
                                source={Track.Source.Camera}
                                className="backdrop-blur-lg bg-white/10 hover:bg-white/20 transition-all shadow-lg"
                                style={{
                                    border: "1px solid rgba(255,255,255,0.1)",
                                    borderRadius: "50%",
                                    width: "45px",
                                    height: "45px",
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
                                    width: "45px",
                                    height: "45px",
                                    borderRadius: "50%",
                                    background: "rgba(0,180,204,0.3)",
                                    backdropFilter: "blur(12px)",
                                    border: "1px solid rgba(0,180,204,0.4)",
                                    fontSize: "18px",
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
                        </div>
                    )}

                    {['❤️', '👍', '👏'].map(emoji => (
                        <button
                            key={emoji}
                            onClick={() => handleReaction(emoji)}
                            className="hover:scale-110 active:scale-90 transition-transform"
                            style={{
                                width: "45px",
                                height: "45px",
                                borderRadius: "50%",
                                background: "rgba(0,0,0,0.3)",
                                backdropFilter: "blur(12px)",
                                border: "1px solid rgba(255,255,255,0.15)",
                                fontSize: "20px",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                cursor: "pointer",
                                boxShadow: "0 4px 10px rgba(0,0,0,0.3)"
                            }}
                        >
                            {emoji}
                        </button>
                    ))}
                </div>
            )}

            {/* Top Unified Dashboard (Consolidated Bidding & Info) */}
            {!isBroadcastEnded && (
                <div style={{
                    position: "absolute",
                    top: "20px",
                    left: "50%",
                    transform: "translateX(-50%)",
                    width: "auto",
                    minWidth: "320px",
                    padding: "8px 16px",
                    background: "rgba(0, 0, 0, 0.4)",
                    backdropFilter: "blur(25px)",
                    WebkitBackdropFilter: "blur(25px)",
                    borderRadius: "100px",
                    border: "1px solid rgba(255, 255, 255, 0.2)",
                    boxShadow: "0 10px 40px rgba(0, 0, 0, 0.5)",
                    zIndex: 200,
                    display: "flex",
                    alignItems: "center",
                    gap: "20px",
                    color: "white"
                }}>
                    {/* Status & Price Section */}
                    <div style={{ display: "flex", alignItems: "center", gap: "16px", borderRight: "1px solid rgba(255,255,255,0.1)", paddingRight: "16px" }}>
                        <div>
                            <span style={{ fontSize: "0.6rem", opacity: 0.7, display: "block", textTransform: "uppercase", letterSpacing: "1px" }}>
                                {auctionStatus === "ACTIVE" ? "CANLI TEQLİF" : "BAŞLANGIÇ"}
                            </span>
                            <span className={`tabular-nums font-extrabold tracking-tighter ${flashBid ? 'bid-flash' : ''}`} style={{ fontSize: "1.2rem", color: "#22c55e", display: "flex", alignItems: "baseline", gap: "2px" }}>
                                {new Intl.NumberFormat("tr-TR").format(liveHighestBid || (startingBid ?? 0))}
                                <span style={{ fontSize: "0.85rem", opacity: 0.6 }}>₺</span>
                            </span>
                        </div>

                        {!isOwner && auctionStatus === "IDLE" && (
                            <div style={{ fontSize: "0.75rem", fontWeight: 700, opacity: 0.8, background: "rgba(255,255,255,0.1)", padding: "4px 12px", borderRadius: "100px" }}>
                                ⏳ Bekleniyor
                            </div>
                        )}

                        {auctionStatus === "ACTIVE" && (
                            <div className="flex items-center gap-2" style={{ fontSize: "0.7rem", fontWeight: 900, color: "#22c55e", background: "rgba(34, 197, 94, 0.1)", padding: "4px 10px", borderRadius: "100px", border: "1px solid rgba(34, 197, 94, 0.2)" }}>
                                <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
                                CANLI
                            </div>
                        )}
                    </div>

                    {/* Action Controls Section */}
                    {isOwner ? (
                        <div style={{ display: "flex", gap: "8px" }}>
                            {auctionStatus === "IDLE" ? (
                                <button onClick={startCountdown} disabled={countdown > 0} style={{ background: "var(--primary)", color: "white", border: "none", borderRadius: "100px", padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer" }}>
                                    Açık Arttırmayı Başlat
                                </button>
                            ) : (
                                <>
                                    <button onClick={startCountdown} style={{ background: "rgba(239, 68, 68, 0.1)", color: "#ef4444", border: "1px solid rgba(239, 68, 68, 0.3)", borderRadius: "100px", padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer" }}>
                                        ⏳ Sayaç
                                    </button>
                                    <button onClick={handleAccept} style={{ background: "#22c55e", color: "white", border: "none", borderRadius: "100px", padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer" }}>
                                        Onayla ve Sat
                                    </button>
                                </>
                            )}
                            <button onClick={() => handleEndBroadcast()} style={{ background: "rgba(255,255,255,0.1)", color: "white", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "100px", padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer" }}>
                                Yayını Bitir
                            </button>
                        </div>
                    ) : (
                        <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                            {auctionStatus === "ACTIVE" && (
                                <BidMiniForm adId={adId} currentHighest={liveHighestBid} minStep={minBidStep} startingBid={startingBid} />
                            )}
                            {buyItNowPrice && (
                                <button
                                    onClick={() => {
                                        if (confirm(`${new Intl.NumberFormat("tr-TR").format(buyItNowPrice)} ₺ fiyata hemen almak istetliyor musunuz?`)) {
                                            handleBuyNow();
                                        }
                                    }}
                                    style={{
                                        background: "linear-gradient(135deg, #FFD700 0%, #FFA500 100%)",
                                        color: "black",
                                        border: "none",
                                        borderRadius: "100px",
                                        padding: "8px 16px",
                                        fontSize: "0.8rem",
                                        fontWeight: 900,
                                        cursor: "pointer",
                                        boxShadow: "0 4px 15px rgba(255, 165, 0, 0.3)",
                                        whiteSpace: "nowrap"
                                    }}
                                >
                                    HEMEN AL: {new Intl.NumberFormat("tr-TR").format(buyItNowPrice)} ₺
                                </button>
                            )}
                        </div>
                    )}
                </div>
            )}

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

            {/* Repositioned Chat Area (Below Video) */}
            {!isBroadcastEnded && (
                <div style={{
                    position: "absolute",
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: "180px",
                    background: "linear-gradient(to top, rgba(0,0,0,0.95) 0%, rgba(0,0,0,0.4) 60%, transparent 100%)",
                    display: "flex",
                    flexDirection: "column",
                    padding: "10px 20px",
                    zIndex: 100
                }}>
                    <div style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: "6px", paddingBottom: "10px" }}>
                        {messages.map((msg: any) => (
                            <div key={msg.id} style={{
                                background: "rgba(255,255,255,0.08)",
                                backdropFilter: "blur(4px)",
                                padding: "4px 12px",
                                borderRadius: "8px",
                                maxWidth: "max-content",
                                fontSize: "0.85rem",
                                animation: "slideUp 0.3s ease-out"
                            }}>
                                <span style={{ color: "#00B4CC", fontWeight: 800, marginRight: "8px" }}>{msg.sender}:</span>
                                <span style={{ color: "white" }}>{msg.text}</span>
                            </div>
                        ))}
                    </div>

                    <form onSubmit={handleSendChat} style={{
                        display: "flex",
                        gap: "10px",
                        background: "rgba(255,255,255,0.1)",
                        backdropFilter: "blur(10px)",
                        border: "1px solid rgba(255,255,255,0.1)",
                        borderRadius: "100px",
                        padding: "4px 4px 4px 16px",
                        marginBottom: "10px"
                    }}>
                        <input
                            type="text"
                            value={chatText}
                            onChange={(e) => setChatText(e.target.value)}
                            placeholder="Sohbet et..."
                            style={{ background: "transparent", border: "none", outline: "none", color: "white", flex: 1, fontSize: "0.9rem" }}
                        />
                        <button type="submit" style={{ background: "#00B4CC", color: "white", border: "none", borderRadius: "100px", width: "36px", height: "36px", fontWeight: "bold" }}>➔</button>
                    </form>
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
                    width: "100px",
                    height: "38px", // Explicit height for alignment
                    background: "rgba(255,255,255,0.15)",
                    border: "1px solid rgba(255,255,255,0.2)",
                    borderRadius: "100px",
                    padding: "0 12px",
                    color: "white",
                    fontSize: "0.85rem",
                    textAlign: "center",
                    fontWeight: 700,
                    outline: "none"
                }}
            />
            <button
                type="submit"
                disabled={loading}
                style={{
                    height: "38px", // Exact same height as input
                    background: "var(--primary)",
                    color: "white",
                    border: "none",
                    borderRadius: "100px",
                    padding: "0 16px",
                    fontSize: "0.8rem",
                    fontWeight: 800,
                    cursor: "pointer",
                    boxShadow: "0 4px 15px rgba(0, 188, 212, 0.4)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    whiteSpace: "nowrap" // Prevent word wrap
                }}
            >
                {loading ? "..." : "teqlif ver"}
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
