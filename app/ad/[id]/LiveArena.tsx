"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer, useTracks, VideoTrack, useDataChannel, useRoomContext, TrackToggle } from "@livekit/components-react";
import { Track } from "livekit-client";
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
            style={{ height: "calc(100vh - 200px)", minHeight: "450px", maxHeight: "700px", borderRadius: "1.5rem", overflow: "hidden", position: "relative" }}
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

    useDataChannel((msg) => {
        try {
            const dataStr = new TextDecoder().decode(msg.payload);

            // Handle numeric "New Bid" message prefix text
            if (dataStr.startsWith('🔥 Yeni Teklif: ₺')) {
                const amount = parseInt(dataStr.replace('🔥 Yeni Teklif: ₺', '').replace(/\./g, ''), 10);
                if (!isNaN(amount)) {
                    setLiveHighestBid(amount);
                    setLastAcceptedBidId(null); // Reset on new bid
                }
                return;
            }

            const dataObj = JSON.parse(dataStr);
            if (dataObj.type === 'NEW_BID') {
                setLiveHighestBid(dataObj.amount);
                setLiveHighestBidId(dataObj.bidId); // TRUTH: Save exact ID
                setLiveHighestBidderId(dataObj.bidderId);
                setLastAcceptedBidId(null);
            } else if (dataObj.type === 'BID_ACCEPTED') {
                setLiveHighestBid(dataObj.amount);
                setLiveHighestBidId(dataObj.bidId);
                setLiveHighestBidderId(dataObj.bidderId);
                setLastAcceptedBidId(dataObj.bidId);
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
            }
        } catch (e) {
            // Ignore non-json
        }
    });

    if (tracks.length === 0) {
        return (
            <div style={{ width: "100%", height: "100%", display: "flex", justifyContent: "center", alignItems: "center", background: "#111" }}>
                <span style={{ color: "#aaa" }}>Yayın bekleniyor...</span>
            </div>
        );
    }

    const hostTrack = tracks[0];
    const guestTrack = tracks.length > 1 ? tracks[1] : null;

    return (
        <div style={{ position: "relative", width: "100%", height: "100%", background: "black" }}>
            {/* Host Full Screen */}
            <VideoTrack trackRef={hostTrack} style={{ width: "100%", height: "100%", objectFit: "contain" }} />

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
                        style={{
                            background: "rgba(0,0,0,0.5)",
                            border: "1px solid rgba(255,255,255,0.2)",
                            borderRadius: "50%",
                            width: "40px",
                            height: "40px",
                            color: "white",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            cursor: "pointer"
                        }}
                    />
                    <TrackToggle
                        source={Track.Source.Camera}
                        style={{
                            background: "rgba(0,0,0,0.5)",
                            border: "1px solid rgba(255,255,255,0.2)",
                            borderRadius: "50%",
                            width: "40px",
                            height: "40px",
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
            <BiddingOverlay
                adId={adId}
                sellerId={sellerId}
                isOwner={isOwner}
                buyItNowPrice={buyItNowPrice}
                startingBid={startingBid}
                minBidStep={minBidStep}
                currentHighestBid={liveHighestBid}
                lastAcceptedBidId={lastAcceptedBidId}
                liveHighestBidId={liveHighestBidId} // NEW: Pass the tracked Bid ID
                liveHighestBidderId={liveHighestBidderId}
                auctionStatus={auctionStatus}
                setMessages={setMessages}
            />

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

            {/* Ephemeral Chat Overlay */}
            <div style={{
                position: "absolute",
                bottom: "120px",
                left: "20px",
                width: "260px",
                display: "flex",
                flexDirection: "column",
                gap: "8px",
                zIndex: 150,
                pointerEvents: "none"
            }}>
                {messages.map((m) => (
                    <div key={m.id} style={{
                        background: "rgba(0,0,0,0.4)",
                        backdropFilter: "blur(10px)",
                        padding: "6px 14px",
                        borderRadius: "12px",
                        color: "white",
                        fontSize: "0.85rem",
                        animation: "fadeInUp 0.3s ease-out"
                    }}>
                        <strong style={{ color: "rgba(255,255,255,0.7)", marginRight: "6px" }}>{m.sender}:</strong>
                        {m.text}
                        {isOwner && m.senderId && (
                            <button
                                onClick={() => {
                                    if (room && m.senderId) {
                                        const payload = JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: m.senderId });
                                        room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                                        alert("Sahneye davet gönderildi!");
                                    }
                                }}
                                style={{
                                    marginLeft: '8px',
                                    background: 'rgba(0, 180, 204, 0.3)',
                                    border: '1px solid rgba(0, 180, 204, 0.6)',
                                    borderRadius: '12px',
                                    color: '#00B4CC',
                                    fontSize: '0.7rem',
                                    padding: '2px 8px',
                                    cursor: 'pointer'
                                }}
                            >
                                🎤 Davet
                            </button>
                        )}
                    </div>
                ))}
            </div>

            <style jsx>{`
                @keyframes fadeInUp {
                    from { opacity: 0; transform: translateY(10px); }
                    to { opacity: 1; transform: translateY(0); }
                }
                @keyframes slideDown {
                    from { opacity: 0; transform: translate(-50%, -20px); }
                    to { opacity: 1; transform: translate(-50%, 0); }
                }
            `}</style>
        </div>
    );
}

function BiddingOverlay({ adId, sellerId, isOwner, buyItNowPrice, startingBid, minBidStep, currentHighestBid, lastAcceptedBidId, liveHighestBidId, liveHighestBidderId, auctionStatus, setMessages }: any) {
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
            bottom: "20px",
            left: "50%",
            transform: "translateX(-50%)",
            width: "auto",
            minWidth: isOwner ? "320px" : "400px",
            padding: "8px 16px",
            background: "rgba(0, 0, 0, 0.4)",
            backdropFilter: "blur(20px)",
            WebkitBackdropFilter: "blur(20px)",
            borderRadius: "100px",
            border: "1px solid rgba(255, 255, 255, 0.15)",
            boxShadow: "0 10px 40px rgba(0, 0, 0, 0.4)",
            zIndex: 100,
            display: "flex",
            alignItems: "center",
            gap: "16px",
            color: "white"
        }}>
            {/* Current Price Info */}
            <div style={{ whiteSpace: "nowrap", borderRight: "1px solid rgba(255,255,255,0.1)", paddingRight: "10px", display: "flex", alignItems: "center", gap: "6px" }}>
                <div>
                    <span style={{ fontSize: "0.6rem", opacity: 0.7, display: "block", textTransform: "uppercase", letterSpacing: "1px" }}>Güncel</span>
                    <span style={{ fontSize: "1rem", fontWeight: 800, color: "#22c55e" }}>{formattedPrice(currentHighestBid || (startingBid ?? 0))}</span>
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
                                Mezatı Başlat
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
                                Mezatı Bitir
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
                            Mezat Bekleniyor...
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

            {/* Chat Input */}
            <form onSubmit={handleSendChat} style={{
                marginLeft: "8px",
                display: "flex",
                alignItems: "center",
                gap: "8px"
            }}>
                <input
                    type="text"
                    value={chatText}
                    onChange={(e) => setChatText(e.target.value)}
                    placeholder="Sohbete katıl..."
                    style={{
                        width: "140px",
                        padding: "8px 16px",
                        background: "rgba(255, 255, 255, 0.15)",
                        border: "1px solid rgba(255, 255, 255, 0.2)",
                        borderRadius: "100px",
                        color: "white",
                        fontSize: "0.85rem",
                        outline: "none"
                    }}
                />
                <button
                    type="submit"
                    style={{
                        background: "#00B4CC",
                        border: "none",
                        width: "34px",
                        height: "34px",
                        borderRadius: "50%",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        cursor: "pointer",
                        color: "white"
                    }}
                >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                        <line x1="22" y1="2" x2="11" y2="13"></line>
                        <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
                    </svg>
                </button>
            </form>
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
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            zIndex: 50,
        }}>
            <div style={{ background: "white", padding: "24px", borderRadius: "12px", maxWidth: "300px", textAlign: "center" }}>
                <h3 style={{ marginTop: 0, color: "var(--primary-dark)" }}>Sahneye Davet!</h3>
                <p style={{ fontSize: "0.9rem", color: "#666" }}>
                    Yayıncı sizi sahneye davet ediyor. Kabul ediyor musunuz?
                </p>
                <div style={{ display: "flex", gap: "12px", justifyContent: "center", marginTop: "16px" }}>
                    <button
                        onClick={() => setInviteVisible(false)}
                        style={{ padding: "8px 16px", background: "#ccc", border: "none", borderRadius: "6px", cursor: "pointer" }}
                    >
                        Reddet
                    </button>
                    <button
                        onClick={async () => {
                            setInviteVisible(false);
                            await room.disconnect();
                            setRole("guest");
                        }}
                        style={{ padding: "8px 16px", background: "var(--primary)", color: "white", border: "none", borderRadius: "6px", cursor: "pointer", fontWeight: "bold" }}
                    >
                        Kabul Et
                    </button>
                </div>
            </div>
        </div>
    );
}
