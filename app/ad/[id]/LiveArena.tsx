"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer, useTracks, VideoTrack, useDataChannel, useRoomContext } from "@livekit/components-react";
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
    currentHighestBid?: number;
}

export default function LiveArena({
    roomId,
    adId,
    sellerId,
    isOwner,
    buyItNowPrice,
    startingBid,
    minBidStep = 1,
    currentHighestBid = 0
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
                currentHighestBid={currentHighestBid}
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
    currentHighestBid
}: any) {
    const tracks = useTracks([Track.Source.Camera]);

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

            {/* Bidding Overlay */}
            {!isOwner && (
                <BiddingOverlay
                    adId={adId}
                    sellerId={sellerId}
                    buyItNowPrice={buyItNowPrice}
                    startingBid={startingBid}
                    minBidStep={minBidStep}
                    currentHighestBid={currentHighestBid}
                />
            )}

            {/* Guest PiP Screen */}
            {guestTrack && (
                <div style={{
                    position: "absolute",
                    bottom: "20px",
                    right: "20px",
                    width: "120px",
                    height: "160px",
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
        </div>
    );
}

function BiddingOverlay({ adId, sellerId, buyItNowPrice, startingBid, minBidStep, currentHighestBid }: any) {
    const router = useRouter();
    const { data: session } = useSession();
    const [amount, setAmount] = useState(() => {
        const minAmount = currentHighestBid > 0 ? (currentHighestBid + minBidStep) : (startingBid ?? 1);
        return new Intl.NumberFormat("tr-TR").format(minAmount);
    });
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState<any>(null); // { type: 'success' | 'error', msg: string }

    const formattedPrice = (val: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

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
                // Send initial message
                try {
                    const currentUserId = session?.user?.id;
                    const recipientId = conversation.user1Id === currentUserId ? conversation.user2Id : conversation.user1Id;
                    await fetch('/api/messages', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            conversationId: conversation.id,
                            content: `Merhaba, bu ürünü Hemen Al fiyatı olan ${formattedPrice(buyItNowPrice)} üzerinden satın almak istiyorum.`,
                            recipientId
                        })
                    });
                } catch (e) {
                    console.error("Initial message error", e);
                }
                alert("Satın alma isteği iletildi. Mesajlara yönlendiriliyorsunuz.");
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

    return (
        <div style={{
            position: "absolute",
            bottom: "20px",
            left: "50%",
            transform: "translateX(-50%)",
            width: "auto",
            minWidth: "400px",
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
            <div style={{ whiteSpace: "nowrap", borderRight: "1px solid rgba(255,255,255,0.1)", paddingRight: "16px" }}>
                <span style={{ fontSize: "0.65rem", opacity: 0.7, display: "block", textTransform: "uppercase", letterSpacing: "1px" }}>Güncel</span>
                <span style={{ fontSize: "1.1rem", fontWeight: 800, color: "#22c55e" }}>{formattedPrice(currentHighestBid || (startingBid ?? 0))}</span>
            </div>

            {/* Bid Form Integrated */}
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
                        width: "100px",
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
                        whiteSpace: "nowrap",
                        transition: "transform 0.2s"
                    }}
                    onMouseDown={(e) => e.currentTarget.style.transform = 'scale(0.95)'}
                    onMouseUp={(e) => e.currentTarget.style.transform = 'scale(1)'}
                >
                    {loading ? "..." : "Pey Ver"}
                </button>
            </form>

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
                    fontWeight: 700,
                    boxShadow: "0 4px 12px rgba(0,0,0,0.2)"
                }}>
                    {status.msg}
                </div>
            )}

            {/* Buy Now Button (Sleek) */}
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
                        whiteSpace: "nowrap",
                        boxShadow: "0 4px 15px rgba(255, 165, 0, 0.3)"
                    }}
                >
                    ⚡ Hemen Al
                </button>
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
                // Return to viewer
                setWantsToPublish(false);
                setRole("viewer");
                alert("Sahneden alındınız.");
                room.disconnect(); // Will prompt a reconnect with viewer token
            }
        } catch (e) {
            console.error("Data channel parse error", e);
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
                    Yayıncı sizi sahneye davet ediyor. Kameranız ve mikrofonunuz açılacak. Kabul ediyor musunuz?
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
                            // Set role to guest, will trigger token refetch and reconnect
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
