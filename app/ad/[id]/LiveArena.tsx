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
            className="aspect-video bg-black relative rounded-xl overflow-hidden shadow-2xl"
            style={{ width: "100%", maxHeight: "700px" }}
        >
            <CustomArenaLayout
                adId={adId}
                sellerId={sellerId}
                isOwner={isOwner}
                buyItNowPrice={buyItNowPrice}
                startingBid={startingBid}
                minBidStep={minBidStep}
                initialHighestBid={initialHighestBid}
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
    initialHighestBid
}: any) {
    const room = useRoomContext();
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

    const isBroadcastEnded = isRoomClosed || connectionState === ConnectionState.Disconnected;

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
                    id: Date.now().toString(),
                    text: dataObj.text,
                    sender: dataObj.senderName || "Katılımcı",
                    senderId: dataObj.senderId
                };
                setMessages(prev => [...prev.slice(-4), newMessage]);
                setTimeout(() => {
                    setMessages(prev => prev.filter((m: any) => m.id !== newMessage.id));
                }, 5000);
            } else if (dataObj.type === 'AUCTION_START') {
                setAuctionStatus("ACTIVE");
                setAuctionNotification("📣 MEZAT BAŞLADI!");
                setTimeout(() => setAuctionNotification(null), 5000);
            } else if (dataObj.type === 'AUCTION_END') {
                setAuctionStatus("IDLE");
                setAuctionNotification("📣 MEZAT DURDURULDU");
                setTimeout(() => setAuctionNotification(null), 5000);
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
                <p className="opacity-50 mt-4 font-medium tracking-wide text-sm">Lütfen ayrılmayın, açık artırma birazdan başlayacak.</p>
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

            {/* Bidding Overlay (Unified for Owner and Viewer) */}
            {!isBroadcastEnded && (
                <BiddingOverlay
                    adId={adId}
                    sellerId={sellerId}
                    isOwner={isOwner}
                    buyItNowPrice={buyItNowPrice}
                    startingBid={startingBid}
                    minBidStep={minBidStep}
                    currentHighestBid={liveHighestBid}
                    lastAcceptedBidId={lastAcceptedBidId}
                    liveHighestBidId={liveHighestBidId}
                    liveHighestBidderId={liveHighestBidderId}
                    auctionStatus={auctionStatus}
                    setMessages={setMessages}
                    messages={messages}
                    isBroadcastEnded={isBroadcastEnded}
                    flashBid={flashBid}
                    startCountdown={startCountdown}
                />
            )}

            {/* Auction Status Notification Overlay */}
            {auctionNotification && (
                <div style={{
                    position: "absolute",
                    top: "120px",
                    left: "50%",
                    transform: "translateX(-50%)",
                    background: "rgba(34, 197, 94, 0.95)",
                    color: "white",
                    padding: "16px 32px",
                    borderRadius: "100px",
                    fontWeight: 900,
                    fontSize: "1.2rem",
                    letterSpacing: "1px",
                    boxShadow: "0 10px 30px rgba(0,0,0,0.5)",
                    zIndex: 200,
                    animation: "slideDown 0.5s ease-out"
                }}>
                    {auctionNotification}
                </div>
            )}

            {/* Countdown Gamification Overlay */}
            {countdown > 0 && (
                <div
                    className={countdown <= 10 ? "animate-pulse" : ""}
                    style={{
                        position: "absolute",
                        top: "30%",
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




            <style jsx>{`
                @keyframes fadeInUp {
                    from { opacity: 0; transform: translateY(10px); }
                    to { opacity: 1; transform: translateY(0); }
                }
                @keyframes slideDown {
                    from { opacity: 0; transform: translate(-50%, -20px); }
                    to { opacity: 1; transform: translate(-50%, 0); }
                }
                @keyframes slideUp {
                    from { opacity: 0; transform: translateY(10px); }
                    to { opacity: 1; transform: translateY(0); }
                }
                .bid-flash {
                    animation: flashBidAnim 0.3s ease-out;
                }
                @keyframes flashBidAnim {
                    0% { transform: scale(1); color: #22c55e; }
                    50% { transform: scale(1.15); color: #4ade80; text-shadow: 0 0 15px rgba(74, 222, 128, 0.8); }
                    100% { transform: scale(1); color: #22c55e; }
                }
                @keyframes zoomIn {
                    from { opacity: 0; transform: translate(-50%, -50%) scale(0.5); }
                    to { opacity: 1; transform: translate(-50%, -50%) scale(1); }
                }
            `}</style>
        </div>
    );
}

function BiddingOverlay({ adId, sellerId, isOwner, buyItNowPrice, startingBid, minBidStep, currentHighestBid, lastAcceptedBidId, liveHighestBidId, liveHighestBidderId, auctionStatus, setMessages, messages, isBroadcastEnded, flashBid, startCountdown }: any) {
    const router = useRouter();
    const { data: session } = useSession();
    const [amount, setAmount] = useState("");
    const [chatText, setChatText] = useState("");
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState<any>(null);
    const room = useRoomContext();

    const formattedPrice = (val: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

    // Auto-update bid amount when highest bid changes
    useEffect(() => {
        const nextMin = currentHighestBid > 0 ? (currentHighestBid + minBidStep) : (startingBid ?? 1);
        setAmount(new Intl.NumberFormat("tr-TR").format(nextMin));
    }, [currentHighestBid, minBidStep, startingBid]);

    async function handleBid(e: React.FormEvent) {
        e.preventDefault();
        setLoading(true);
        setStatus(null);

        const rawAmount = parseInt(amount.replace(/\./g, ""), 10);
        const minReq = currentHighestBid > 0 ? (currentHighestBid + minBidStep) : (startingBid ?? 1);

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
                setStatus({ type: 'success', msg: 'Teklif verildi!' });
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

    async function handleAccept() {
        if (!liveHighestBidId) {
            alert("Kabul edilecek bir teklif bulunamadı.");
            return;
        }
        if (!confirm("Dikkat! Bu teklifi kabul edip satışı tamamlıyorsunuz. İlan 'Satıldı' olarak işaretlenecek ve yayın kapanacaktır. Emin misiniz?")) return;

        setLoading(true);
        try {
            // 1. Accept the bid
            const resAccept = await fetch(`/api/bids/${liveHighestBidId}/accept`, { method: "PATCH" });
            if (resAccept.ok) {
                // 2. Finalize the sale
                const resFinalize = await fetch(`/api/bids/${liveHighestBidId}/finalize`, { method: "POST" });
                if (resFinalize.ok) {
                    alert("Satış başarıyla tamamlandı! İlan yayından kaldırıldı.");
                    await handleEndBroadcast(); // End stream
                    return;
                }
            }
            alert("İşlem başarısız.");
        } catch (e) {
            alert("Bağlantı hatası.");
        } finally {
            setLoading(false);
        }
    }

    async function handleCancel() {
        if (!liveHighestBidId) {
            alert("İptal edilecek bir teklif bulunamadı.");
            return;
        }
        if (!confirm("Bunu iptal etmek istediğinize emin misiniz?")) return;
        setLoading(true);
        try {
            const res = await fetch(`/api/bids/${liveHighestBidId}/cancel`, { method: "PATCH" });
            if (res.ok) {
                alert("Teklif iptal edildi.");
                router.refresh();
            } else {
                alert("İşlem başarısız.");
            }
        } catch (e) {
            alert("Bağlantı hatası.");
        } finally {
            setLoading(false);
        }
    }

    async function handleStartAuction() {
        if (!room) return;
        setLoading(true);
        try {
            const payload = JSON.stringify({ type: "AUCTION_START" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    }

    async function handleStopAuction() {
        if (!room) return;
        setLoading(true);
        try {
            const payload = JSON.stringify({ type: "AUCTION_END" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
        } catch (e) {
            console.error(e);
        }
        setLoading(false);
    }

    async function handleEndBroadcast() {
        if (!confirm("Yayını bitirmek ve odadan çıkmak istediğinize emin misiniz?")) return;
        setLoading(true);
        try {
            // First send ROOM_CLOSED channel message to kick everyone else
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
            } else {
                alert("Yayın sonlandırılamadı.");
            }
        } catch (e) {
            alert("Bağlantı hatası.");
        } finally {
            setLoading(false);
        }
    }

    async function handleBuyNow() {
        if (!buyItNowPrice) return;
        if (!confirm(`${formattedPrice(buyItNowPrice)} fiyata hemen almak istiyor musunuz?`)) return;
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
            } else {
                alert("İşlem başarısız.");
            }
        } catch (e) {
            alert("Bağlantı hatası.");
        } finally {
            setLoading(false);
        }
    }

    async function handleSendChat(e: React.FormEvent) {
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

            // Local echo
            const newMessage = {
                id: Date.now().toString(),
                text: chatText.trim(),
                sender: session?.user?.name || "Ben"
            };
            setMessages((prev: any) => [...prev.slice(-4), newMessage]);
            setTimeout(() => {
                setMessages((prev: any) => prev.filter((m: any) => m.id !== newMessage.id));
            }, 5000);

            setChatText("");
        } catch (e) {
            console.error("Chat error:", e);
        }
    }

    return (
        <div style={{
            position: "absolute",
            top: "20px",
            left: "50%",
            transform: "translateX(-50%)",
            width: "auto",
            minWidth: "320px",
            padding: "10px 20px",
            background: "rgba(0, 0, 0, 0.4)",
            backdropFilter: "blur(20px)",
            WebkitBackdropFilter: "blur(20px)",
            borderRadius: "100px",
            border: "1px solid rgba(255, 255, 255, 0.15)",
            boxShadow: "0 10px 40px rgba(0, 0, 0, 0.4)",
            zIndex: 100,
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            gap: "24px",
            color: "white"
        }}>
            {/* Current Price Info */}
            <div style={{ whiteSpace: "nowrap", borderRight: "1px solid rgba(255,255,255,0.1)", paddingRight: "10px", display: "flex", alignItems: "center", gap: "6px" }}>
                <div>
                    <span style={{ fontSize: "0.6rem", opacity: 0.7, display: "block", textTransform: "uppercase", letterSpacing: "1px" }}>Güncel</span>
                    <span className={`tabular-nums font-extrabold tracking-tighter transition-all duration-300 ${flashBid ? 'bid-flash' : ''}`} style={{ fontSize: "1.2rem", color: "#22c55e", display: "flex", alignItems: "baseline", gap: "2px" }}>
                        {new Intl.NumberFormat("tr-TR").format(currentHighestBid || (startingBid ?? 0))}
                        <span className="text-gray-400 font-medium" style={{ fontSize: "0.85rem" }}>₺</span>
                    </span>
                </div>
                {isOwner && currentHighestBid > 0 && liveHighestBidderId && (
                    <button
                        onClick={() => {
                            if (room && liveHighestBidderId) {
                                const payload = JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: liveHighestBidderId });
                                room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                                alert("Sahneye davet gönderildi!");
                            }
                        }}
                        style={{
                            background: "rgba(0, 180, 204, 0.2)",
                            color: "#00B4CC",
                            border: "1px solid rgba(0, 180, 204, 0.4)",
                            borderRadius: "100px",
                            padding: "4px 8px",
                            fontSize: "0.65rem",
                            fontWeight: 800,
                            cursor: "pointer",
                            display: "flex",
                            alignItems: "center",
                            gap: "4px",
                            flexShrink: 0
                        }}
                    >
                        🎤 Davet Et
                    </button>
                )}
            </div>

            {isOwner ? (
                /* Host Controls */
                <div style={{ display: "flex", alignItems: "center", gap: "10px", flex: 1, justifyContent: "space-between" }}>
                    <div style={{ display: "flex", gap: "8px" }}>
                        {auctionStatus === "IDLE" ? (
                            <button
                                onClick={handleStartAuction}
                                disabled={loading}
                                style={{
                                    background: "var(--primary)", color: "white", border: "none", borderRadius: "100px",
                                    padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer",
                                    boxShadow: "0 4px 12px rgba(0, 188, 212, 0.3)"
                                }}
                            >
                                Açık Artırmayı Başlat
                            </button>
                        ) : (
                            <button
                                onClick={handleStopAuction}
                                disabled={loading}
                                style={{
                                    background: "#f59e0b", color: "white", border: "none", borderRadius: "100px",
                                    padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer",
                                    boxShadow: "0 4px 12px rgba(245, 158, 11, 0.3)"
                                }}
                            >
                                Açık Artırmayı Bitir
                            </button>
                        )}
                        {auctionStatus === "ACTIVE" && (
                            <button
                                onClick={startCountdown}
                                style={{
                                    background: "rgba(239, 68, 68, 0.1)", color: "#ef4444", border: "1px solid rgba(239, 68, 68, 0.5)", borderRadius: "100px",
                                    padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer",
                                    transition: "all 0.2s"
                                }}
                            >
                                ⏳ Sayacı Başlat
                            </button>
                        )}
                        <button
                            onClick={handleEndBroadcast}
                            disabled={loading}
                            style={{
                                background: "rgba(239, 68, 68, 0.1)", color: "#ef4444", border: "1px solid rgba(239, 68, 68, 0.5)", borderRadius: "100px",
                                padding: "8px 16px", fontSize: "0.8rem", fontWeight: 800, cursor: "pointer",
                                transition: "all 0.2s"
                            }}
                        >
                            Yayını Bitir
                        </button>
                    </div>

                    <div style={{ display: "flex", gap: "8px" }}>
                        <button
                            onClick={handleCancel}
                            disabled={loading || currentHighestBid === 0 || !liveHighestBidId}
                            style={{
                                background: "rgba(255, 255, 255, 0.15)",
                                color: "white",
                                border: "1px solid rgba(255, 255, 255, 0.3)",
                                borderRadius: "100px",
                                padding: "8px 16px",
                                fontSize: "0.8rem",
                                fontWeight: 800,
                                cursor: "pointer",
                                transition: "all 0.2s"
                            }}
                        >
                            Reddet
                        </button>
                        <button
                            onClick={handleAccept}
                            disabled={loading || currentHighestBid === 0 || !liveHighestBidId}
                            style={{
                                background: "#22c55e",
                                color: "white",
                                border: "none",
                                borderRadius: "100px",
                                padding: "8px 18px",
                                fontSize: "0.85rem",
                                fontWeight: 800,
                                cursor: "pointer",
                                transition: "transform 0.2s",
                                boxShadow: "0 4px 15px rgba(34, 197, 94, 0.4)"
                            }}
                        >
                            {loading ? "..." : "Onayla ve Sat"}
                        </button>
                    </div>
                </div>
            ) : (
                /* Viewer Controls */
                <>
                    {auctionStatus === "ACTIVE" ? (
                        <form onSubmit={handleBid} style={{ display: "flex", alignItems: "center", gap: "8px", flex: 1 }}>
                            <input
                                type="text"
                                value={amount}
                                onChange={(e) => {
                                    const val = e.target.value.replace(/[^0-9]/g, "");
                                    setAmount(val ? new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)) : "");
                                }}
                                placeholder="Miktar"
                                style={{
                                    width: "90px",
                                    padding: "6px 12px",
                                    background: "rgba(255, 255, 255, 0.1)",
                                    border: "1px solid rgba(255, 255, 255, 0.2)",
                                    borderRadius: "100px",
                                    color: "white",
                                    fontSize: "0.9rem",
                                    textAlign: "center",
                                    outline: "none"
                                }}
                            />
                            <button
                                type="submit"
                                disabled={loading}
                                style={{
                                    background: "var(--primary)",
                                    color: "white",
                                    border: "none",
                                    borderRadius: "100px",
                                    padding: "8px 16px",
                                    fontSize: "0.85rem",
                                    fontWeight: 700,
                                    cursor: "pointer",
                                    transition: "all 0.2s"
                                }}
                            >
                                {loading ? "..." : "Pey Ver"}
                            </button>
                        </form>
                    ) : (
                        <div style={{ flex: 1, textAlign: "center", fontSize: "0.85rem", fontWeight: 700, color: "rgba(255,255,255,0.6)" }}>
                            Açık Artırma Bekleniyor...
                        </div>
                    )}

                    {buyItNowPrice && (
                        <button
                            onClick={handleBuyNow}
                            disabled={loading}
                            style={{
                                background: "linear-gradient(135deg, #FFD700 0%, #FFA500 100%)",
                                color: "black",
                                border: "none",
                                borderRadius: "100px",
                                padding: "8px 16px",
                                fontSize: "0.8rem",
                                fontWeight: 800,
                                cursor: "pointer",
                                boxShadow: "0 4px 15px rgba(255, 165, 0, 0.3)"
                            }}
                        >
                            ⚡ Hemen Al
                        </button>
                    )}
                </>
            )}

            {/* Right Side Overlay (For Viewer only; Host has a separate panel below video) */}
            {!isOwner && (
                <div style={{
                    position: "absolute",
                    bottom: "100px",
                    right: "20px",
                    width: "320px",
                    zIndex: 100
                }}>
                    {auctionStatus === "ACTIVE" ? (
                        <BidForm
                            adId={adId}
                            currentHighest={currentHighestBid || (startingBid ?? 0)}
                            minStep={minBidStep}
                            startingBid={startingBid}
                            formattedPrice={formattedPrice}
                        />
                    ) : (
                        <div style={{
                            background: "rgba(0,0,0,0.6)",
                            backdropFilter: "blur(10px)",
                            border: "1px solid rgba(255,255,255,0.1)",
                            borderRadius: "1rem",
                            padding: "1.5rem",
                            color: "white",
                            textAlign: "center",
                            boxShadow: "0 10px 30px rgba(0,0,0,0.5)"
                        }}>
                            <div style={{ fontSize: "2.5rem", marginBottom: "12px", animation: "pulse 2s infinite" }}>⏳</div>
                            <h3 style={{ margin: "0 0 8px 0", fontSize: "1.2rem", fontWeight: 700 }}>Açık Artırma Bekleniyor</h3>
                            <p style={{ margin: 0, opacity: 0.8, fontSize: "0.9rem", lineHeight: 1.5 }}>Yayıncı açık artırmayı başlattığında buradan teklif verebileceksiniz.</p>
                            {buyItNowPrice && (
                                <button
                                    onClick={handleBuyNow}
                                    style={{
                                        marginTop: "20px",
                                        width: "100%",
                                        background: "linear-gradient(135deg, #FFD700 0%, #FFA500 100%)",
                                        color: "black",
                                        border: "none",
                                        borderRadius: "0.75rem",
                                        padding: "14px",
                                        fontWeight: 800,
                                        fontSize: "1rem",
                                        cursor: "pointer",
                                        boxShadow: "0 4px 15px rgba(255, 165, 0, 0.3)"
                                    }}
                                >
                                    HEMEN AL: {formattedPrice(buyItNowPrice)}
                                </button>
                            )}
                        </div>
                    )}
                </div>
            )}

            {/* Status Indicator */}
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
        </div>
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
                setStatus({ type: 'success', msg: 'Teklif verildi!' });
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
            <h3 style={{ margin: 0, fontSize: "1.2rem", fontWeight: "bold", textAlign: "center" }}>Teklif Ver</h3>
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
                {loading ? "..." : "Pey Ver"}
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
