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
            <div className="flex flex-col items-center justify-center w-full h-[60vh] bg-neutral-950 text-white rounded-2xl">
                <div className="w-10 h-10 border-4 border-emerald-500 border-t-transparent rounded-full animate-spin mb-4"></div>
                <p className="text-lg font-bold tracking-widest animate-pulse">Canlı yayına bağlanılıyor...</p>
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
            className="w-full h-full bg-neutral-950"
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
                isQuickLive={isQuickLive}
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

    const [finalizedWinner, setFinalizedWinner] = useState<string | null>(null);
    const [finalizedAmount, setFinalizedAmount] = useState<number | null>(null);
    const [showFinalization, setShowFinalization] = useState(false);
    const [auctionResult, setAuctionResult] = useState<{ winnerName: string; price: number } | null>(null);
    const [showSoldOverlay, setShowSoldOverlay] = useState<boolean>(true);
    const [countdown, setCountdown] = useState(0);
    const [reactions, setReactions] = useState<{ id: string, emoji: string, left: number }[]>([]);
    const [lastReactionTime, setLastReactionTime] = useState(0);
    const [loading, setLoading] = useState(false);

    const formattedPrice = (val: number) => new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

    const fireConfetti = useCallback(() => {
        const opts = { particleCount: 140, spread: 75, startVelocity: 55, gravity: 0.8, colors: ['#FFD700', '#FFA500', '#FF6B35', '#00B4CC', '#FFFFFF', '#22c55e'] };
        confetti({ ...opts, origin: { x: 0.05, y: 1 }, angle: 65 });
        confetti({ ...opts, origin: { x: 0.95, y: 1 }, angle: 115 });
        setTimeout(() => {
            confetti({ ...opts, particleCount: 80, origin: { x: 0.2, y: 0.8 }, angle: 80 });
            confetti({ ...opts, particleCount: 80, origin: { x: 0.8, y: 0.8 }, angle: 100 });
        }, 400);
    }, []);

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
                    if (room) {
                        const soldPayload = JSON.stringify({ type: "AUCTION_SOLD", winnerId: liveHighestBidderId, winnerName: liveHighestBidderName || liveHighestBidderId || "Katılımcı", price: liveHighestBid });
                        room.localParticipant.publishData(new TextEncoder().encode(soldPayload), { reliable: true });

                        const payloadEnd = JSON.stringify({ type: "AUCTION_END" });
                        room.localParticipant.publishData(new TextEncoder().encode(payloadEnd), { reliable: true });

                        const payloadFinalized = JSON.stringify({ type: "SALE_FINALIZED", winnerName: liveHighestBidderName || liveHighestBidderId || "Katılımcı", amount: liveHighestBid });
                        room.localParticipant.publishData(new TextEncoder().encode(payloadFinalized), { reliable: true });
                    }

                    if (liveHighestBidderId) {
                        fetch("/api/livekit/finalize", {
                            method: "POST", headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ adId, winnerId: liveHighestBidderId, finalPrice: liveHighestBid, isQuickLive }),
                        }).catch(console.error);
                    }
                    setCountdown(0);
                    setAuctionStatus("IDLE");
                }
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    }, [liveHighestBidId, liveHighestBidderId, liveHighestBidderName, liveHighestBid, room, adId, isQuickLive]);

    const handleReject = useCallback(async () => {
        if (!liveHighestBidId) return;
        if (!confirm("Bu teqlifi reddetmek istediğinize emin misiniz?")) return;
        setLoading(true);
        try {
            const res = await fetch(`/api/bids/${liveHighestBidId}/reject`, { method: "PATCH" });
            if (res.ok) {
                setLiveHighestBid(initialHighestBid);
                setLiveHighestBidId(null);
                setLiveHighestBidderId(null);
                setLiveHighestBidderName(null);

                if (room) {
                    const payload = JSON.stringify({ type: "BID_REJECTED", bidId: liveHighestBidId, bidderId: liveHighestBidderId });
                    room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                }
            }
        } catch (e) { console.error(e); }
        finally { setLoading(false); }
    }, [liveHighestBidId, liveHighestBidderId, room, initialHighestBid]);

    const handleEndBroadcast = async (skipConfirm = false) => {
        if (!skipConfirm && !confirm("Yayını bitirmek istiyor musunuz?")) return;
        setLoading(true);
        try {
            if (room) {
                const payload = JSON.stringify({ type: "ROOM_CLOSED" });
                await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            }
            const res = await fetch(`/api/ads/${adId}/live`, {
                method: "POST", headers: { "Content-Type": "application/json" },
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
        if (!confirm("Yeni ürüne geçmek/Sıfırlamak istediğinize emin misiniz?")) return;
        setLoading(true);
        try {
            const res = await fetch('/api/livekit/reset', {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ adId })
            });
            if (res.ok) {
                const payload = JSON.stringify({ type: "AUCTION_RESET" });
                await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
                setLiveHighestBid(initialHighestBid);
                setLiveHighestBidId(null);
                setLiveHighestBidderId(null);
                setLiveHighestBidderName(null);
                setAuctionStatus("ACTIVE");
            }
        } catch (err) { console.error(err); }
        finally { setLoading(false); }
    };

    const isBroadcastEnded = isRoomClosed || connectionState === ConnectionState.Disconnected;

    const addReaction = useCallback((emoji: string) => {
        const newReaction = { id: Date.now().toString() + Math.random(), emoji, left: Math.random() * 60 + 20 };
        setReactions(prev => [...prev.slice(-15), newReaction]);
        setTimeout(() => setReactions(prev => prev.filter(r => r.id !== newReaction.id)), 2500);
    }, []);

    const handleReaction = useCallback(async (emoji: string) => {
        const now = Date.now();
        if (now - lastReactionTime < 500) return;
        setLastReactionTime(now);

        if (!room) return;
        const payload = JSON.stringify({ type: "REACTION", emoji, userId: session?.user?.id });
        try {
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            addReaction(emoji);
        } catch (e) { console.error(e); }
    }, [room, lastReactionTime, session, addReaction]);

    const handleStartAuction = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: true }),
            });
            const payload = JSON.stringify({ type: "AUCTION_START" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("ACTIVE");
            setAuctionNotification("📣 AÇIK ARTTIRMA BAŞLADI!");
            setTimeout(() => setAuctionNotification(null), 4000);
        } catch (e) { console.error(e); }
        setLoading(false);
    }, [room, adId]);

    const handleStopAuction = useCallback(async () => {
        if (!room) return;
        setLoading(true);
        try {
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isAuctionActive: false }),
            });
            const payload = JSON.stringify({ type: "AUCTION_END" });
            await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            setAuctionStatus("IDLE");
            setAuctionNotification("📣 AÇIK ARTTIRMA DURDURULDU");
            setTimeout(() => setAuctionNotification(null), 4000);
        } catch (e) { console.error(e); }
        setLoading(false);
    }, [room, adId]);

    useDataChannel((msg) => {
        try {
            const dataStr = new TextDecoder().decode(msg.payload);
            const dataObj = JSON.parse(dataStr);
            if (dataObj.type === 'NEW_BID' || dataObj.type === 'BID_ACCEPTED') {
                setLiveHighestBid(dataObj.amount);
                setLiveHighestBidId(dataObj.bidId);
                setLiveHighestBidderId(dataObj.bidderId);
                if (dataObj.bidderName) setLiveHighestBidderName(dataObj.bidderName);
                if (dataObj.type === 'BID_ACCEPTED') setLastAcceptedBidId(dataObj.bidId);
                setFlashBid(true);
                setTimeout(() => setFlashBid(false), 300);
            } else if (dataObj.type === 'BID_REJECTED') {
                if (session?.user?.id === dataObj.bidderId) alert("Teklifiniz satıcı tarafından reddedildi.");
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
                    setStageRequests(prev => prev.find(r => r.id === dataObj.userId) ? prev : [...prev, { id: dataObj.userId, name: dataObj.userName || "Katılımcı" }]);
                }
            } else if (dataObj.type === 'SALE_FINALIZED') {
                setFinalizedWinner(dataObj.winnerName || "Katılımcı");
                setFinalizedAmount(dataObj.amount);
                setShowFinalization(true);
                setTimeout(() => setShowFinalization(false), 10000);
            } else if (dataObj.type === 'AUCTION_SOLD') {
                setAuctionResult({ winnerName: dataObj.winnerName || "Katılımcı", price: Number(dataObj.price) || 0 });
                setShowSoldOverlay(true);
                setAuctionStatus("IDLE");
                fireConfetti();
            }
        } catch (e) { }
    });

    const startCountdown = useCallback(() => {
        if (!room) return;
        let counter = 10;
        setCountdown(counter);
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
            <div className="absolute inset-0 flex flex-col justify-center items-center z-50 bg-neutral-950 animate-pulse transition-all">
                <h2 className="text-3xl font-extrabold tracking-widest text-emerald-500">Yayıncı bekleniyor...</h2>
                <p className="opacity-50 mt-4 font-medium tracking-wide text-sm text-white">Lütfen ayrılmayın, açık arttırma birazdan başlayacak.</p>
            </div>
        );
    }

    const hostTrack = tracks[0];
    const guestTrack = tracks.length > 1 ? tracks[1] : null;

    return (
        // ANA KONTEYNER - FULL EKRAN KİLİTLİ (OVERLAY MİMARİSİ)
        <div className="w-full h-[calc(100dvh-70px)] md:h-[calc(100vh-80px)] bg-black relative overflow-hidden font-sans text-white">

            <style>{`
                @keyframes floatUp { 0% { transform: translateY(0) scale(1); opacity: 1; } 100% { transform: translateY(-250px) scale(1.5); opacity: 0; } }
            `}</style>

            {/* ====================================================
                1. KATMAN: VIDEO VE ARKA PLAN (EN ALT)
            ==================================================== */}
            <div className="absolute inset-0 z-0 bg-black">
                {isBroadcastEnded ? (
                    <div className="flex flex-col items-center justify-center w-full h-full bg-neutral-950">
                        <div className="text-5xl mb-4">📡</div>
                        <h2 className="text-2xl font-bold text-white">Yayın Sona Erdi</h2>
                        <p className="text-white/60 mt-2">Yayıncı canlı yayını kapattı.</p>
                    </div>
                ) : hostTrack?.publication?.isMuted ? (
                    <div className="flex flex-col items-center justify-center w-full h-full bg-neutral-900">
                        <div className="text-5xl mb-4 opacity-50">📷</div>
                        <div className="text-white/50 font-bold text-lg">Kamera Kapalı</div>
                    </div>
                ) : (
                    <VideoTrack trackRef={hostTrack} className="w-full h-full object-cover" />
                )}
            </div>

            {/* EKRAN OKUNABİLİRLİĞİ İÇİN GÖLGELENDİRME (GRADIENT) */}
            <div className="absolute inset-0 z-10 pointer-events-none bg-gradient-to-b from-black/60 via-transparent to-black/80" />


            {/* ====================================================
                2. KATMAN: ÜST HUD (PROFİL, İZLEYİCİ, HOST BUTONLARI)
            ==================================================== */}
            {!isBroadcastEnded && (
                <div className="absolute top-4 left-4 right-4 z-50 flex justify-between items-start pointer-events-none">

                    {/* SOL ÜST: Host Bilgisi ve İzleyici */}
                    <div className="flex flex-col gap-2 pointer-events-auto">
                        <div className="flex items-center bg-black/40 backdrop-blur-md rounded-full p-1 pr-4 border border-white/10 shadow-lg">
                            <div className="w-10 h-10 rounded-full bg-red-600 flex items-center justify-center font-bold text-white shadow-inner">
                                {adOwnerName.charAt(0).toUpperCase()}
                            </div>
                            <div className="ml-3 flex flex-col">
                                <span className="text-white text-sm font-bold shadow-sm drop-shadow-md">{adOwnerName}</span>
                                <span className="text-[10px] bg-red-600 text-white px-2 py-0.5 rounded uppercase font-black tracking-wider w-max -mt-0.5 animate-pulse">CANLI</span>
                            </div>
                        </div>
                        <div className="flex items-center gap-1.5 bg-black/40 backdrop-blur-md px-3 py-1.5 rounded-full w-max border border-white/10 shadow-sm">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                            <span className="text-white text-xs font-bold">{participantCount}</span>
                        </div>
                    </div>

                    {/* SAĞ ÜST: Kapat / Mikrofon / Kamera */}
                    <div className="flex flex-col gap-3 items-end pointer-events-auto">
                        {isOwner ? (
                            <>
                                <button onClick={() => handleEndBroadcast()} className="bg-red-600/80 backdrop-blur-md hover:bg-red-500 text-white font-black px-5 py-2.5 rounded-full shadow-lg border border-red-400/50 flex items-center gap-2 transition-all">
                                    <span className="w-2 h-2 rounded-full bg-white animate-pulse"></span>
                                    Bitir
                                </button>
                                <div className="flex gap-2">
                                    <TrackToggle source={Track.Source.Microphone} className="w-11 h-11 rounded-full bg-black/50 backdrop-blur-md border border-white/20 flex items-center justify-center text-white hover:bg-white/20 transition-all shadow-lg" />
                                    <TrackToggle source={Track.Source.Camera} className="w-11 h-11 rounded-full bg-black/50 backdrop-blur-md border border-white/20 flex items-center justify-center text-white hover:bg-white/20 transition-all shadow-lg" />
                                </div>
                                <button onClick={async () => {
                                    try {
                                        const pubs = Array.from(room.localParticipant.videoTrackPublications.values());
                                        const videoPub = pubs.find(p => p.source === Track.Source.Camera);
                                        // @ts-ignore
                                        if (videoPub?.videoTrack) await videoPub.videoTrack.switchCamera();
                                    } catch (e) { }
                                }} className="w-11 h-11 rounded-full bg-black/50 backdrop-blur-md border border-white/20 flex items-center justify-center text-white text-lg hover:bg-white/20 transition-all shadow-lg">🔄</button>

                                {/* Stage Requests Bell */}
                                {stageRequests.length > 0 && (
                                    <button onClick={() => {
                                        const req = stageRequests[0];
                                        if (confirm(`${req.name} sahneye davet edilsin mi?`)) {
                                            room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: req.id })), { reliable: true });
                                        }
                                        setStageRequests(prev => prev.filter(r => r.id !== req.id));
                                    }} className="w-11 h-11 rounded-full bg-blue-600/80 border border-white/50 flex items-center justify-center text-white animate-pulse relative shadow-[0_0_15px_rgba(37,99,235,0.6)]">
                                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M12 2v20"></path><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg>
                                        <span className="absolute -top-1 -right-1 bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full">{stageRequests.length}</span>
                                    </button>
                                )}
                            </>
                        ) : (
                            <button onClick={() => window.location.href = "/"} className="w-10 h-10 rounded-full bg-black/50 backdrop-blur-md border border-white/20 text-white flex items-center justify-center hover:bg-white/20 transition-all shadow-lg">
                                ✕
                            </button>
                        )}
                    </div>
                </div>
            )}


            {/* ====================================================
                3. KATMAN: ALT KONTROLLER (CHAT, AÇIK ARTIRMA KİTİ)
            ==================================================== */}
            {!isBroadcastEnded && (
                <div className="absolute bottom-0 left-0 right-0 p-3 md:p-6 z-40 flex flex-col justify-end pointer-events-none h-[85%]">

                    {/* Yüzen Emojiler */}
                    {reactions.map((r) => (
                        <div key={r.id} className="animate-[floatUp_2.5s_ease-out_forwards] absolute bottom-[20%] text-4xl pointer-events-none z-50 drop-shadow-md" style={{ left: `${r.left}%` }}>
                            {r.emoji}
                        </div>
                    ))}

                    {/* PIP Kamera (Katılımcı) */}
                    {guestTrack && (
                        <div className="absolute top-24 right-4 w-[110px] h-[150px] md:w-[150px] md:h-[200px] rounded-2xl overflow-hidden border-2 border-white/50 shadow-2xl z-40 bg-black pointer-events-auto">
                            {guestTrack?.publication?.isMuted ? (
                                <div className="w-full h-full flex items-center justify-center bg-neutral-800"><div className="text-3xl">📷</div></div>
                            ) : (
                                <VideoTrack trackRef={guestTrack} className="w-full h-full object-cover" />
                            )}
                        </div>
                    )}

                    {/* ANA ALT BÖLÜM (Mesajlar + Açık Artırma) */}
                    <div className="flex flex-col-reverse md:flex-row md:items-end gap-4 w-full relative z-20 pointer-events-none">

                        {/* SOL: SOHBET KUTUSU */}
                        <div className="flex-1 w-full md:max-w-md pointer-events-auto flex flex-col justify-end h-[35vh] overflow-hidden">
                            <div className="overflow-y-auto flex flex-col gap-2 pr-2 pb-2 scrollbar-thin scrollbar-thumb-white/20 scrollbar-track-transparent" style={{ maskImage: 'linear-gradient(to bottom, transparent 0%, black 15%, black 100%)', WebkitMaskImage: 'linear-gradient(to bottom, transparent 0%, black 15%, black 100%)' }}>
                                {chatMessages.map((msg: any, idx: number) => (
                                    <div key={idx} className="bg-black/40 backdrop-blur-md border border-white/10 p-2.5 rounded-2xl rounded-tl-sm w-max max-w-[90%] shadow-md">
                                        <span className="font-bold text-emerald-400 text-[11px] block mb-0.5 tracking-wide">
                                            {msg.from?.name || "Anonim"}
                                        </span>
                                        <span className="text-[13px] text-white leading-tight block break-words drop-shadow-sm">
                                            {msg.message}
                                        </span>
                                    </div>
                                ))}
                            </div>
                        </div>

                        {/* SAĞ: AÇIK ARTIRMA KART VE EMOJİLER */}
                        <div className="w-full md:w-[360px] flex flex-col gap-3 pointer-events-auto shrink-0">

                            {/* Viewer Emojiler */}
                            {!isOwner && (
                                <div className="flex justify-end gap-2 px-1">
                                    {['❤️', '👏', '🔥'].map(emoji => (
                                        <button key={emoji} onClick={() => handleReaction(emoji)} className="w-11 h-11 rounded-full bg-black/50 backdrop-blur-md hover:bg-black/70 border border-white/10 text-xl flex items-center justify-center transition-transform active:scale-90 shadow-lg">
                                            {emoji}
                                        </button>
                                    ))}
                                    <button onClick={() => {
                                        if (confirm("Sahneye katılma isteği göndermek istiyor musunuz?")) {
                                            room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify({ type: "REQUEST_STAGE", userId: session?.user?.id, userName: session?.user?.name })), { reliable: true });
                                        }
                                    }} className="w-11 h-11 rounded-full bg-blue-500/40 backdrop-blur-md border border-blue-500/50 hover:bg-blue-500/60 flex items-center justify-center transition-transform active:scale-90 ml-2 shadow-[0_0_15px_rgba(59,130,246,0.3)]">
                                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
                                    </button>
                                </div>
                            )}

                            {/* Açık Artırma Durum Kartı (Merkez - Sağ) */}
                            <div className="w-full bg-black/60 backdrop-blur-2xl border border-white/10 rounded-[2rem] p-5 shadow-2xl relative overflow-hidden">
                                <div className="absolute -bottom-6 -right-6 text-7xl opacity-[0.03] rotate-12 pointer-events-none">🔨</div>

                                <div className="flex flex-col items-center relative z-10 text-center">
                                    <span className="text-[10px] font-bold text-white/50 tracking-widest mb-1">
                                        {auctionStatus === "ACTIVE" ? "GÜNCEL FİYAT" : "BAŞLANGIÇ FİYATI"}
                                    </span>
                                    <span className={`text-4xl md:text-5xl font-black tabular-nums tracking-tighter ${flashBid ? 'text-white scale-110 drop-shadow-[0_0_20px_rgba(255,255,255,0.8)]' : 'text-emerald-400'} transition-all duration-300`}>
                                        ₺ {new Intl.NumberFormat("tr-TR").format(liveHighestBid || startingBid || 0)}
                                    </span>

                                    {liveHighestBidderName ? (
                                        <div className="mt-3 bg-white/10 px-4 py-1.5 rounded-full text-[13px] font-medium flex items-center gap-2 border border-white/5 shadow-inner">
                                            <span className="text-white/50">LİDER:</span>
                                            <span className="text-emerald-400 font-bold tracking-wide">{liveHighestBidderName}</span>
                                            {isOwner && liveHighestBidderId && (
                                                <button onClick={() => {
                                                    if (confirm(`${liveHighestBidderName} davet edilsin mi?`)) {
                                                        room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: liveHighestBidderId })), { reliable: true });
                                                    }
                                                }} className="ml-1 text-blue-400 hover:text-blue-300">
                                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
                                                </button>
                                            )}
                                        </div>
                                    ) : (
                                        <div className="mt-3 text-[11px] font-bold text-white/40 flex items-center gap-2 bg-black/30 px-3 py-1 rounded-full">
                                            <span className={`w-2 h-2 rounded-full ${auctionStatus === "ACTIVE" ? "bg-emerald-500 animate-pulse" : "bg-orange-500"}`} />
                                            {auctionStatus === "ACTIVE" ? "TEKLİF BEKLENİYOR" : "BAŞLAMASI BEKLENİYOR"}
                                        </div>
                                    )}
                                </div>

                                <div className="mt-4 relative z-10">
                                    {isOwner ? (
                                        <div className="flex flex-col gap-2">
                                            {auctionStatus === "IDLE" ? (
                                                <button onClick={startCountdown} className="w-full py-3.5 bg-gradient-to-r from-emerald-500 to-emerald-600 rounded-xl font-black text-white shadow-[0_4px_20px_rgba(16,185,129,0.4)] active:scale-[0.98] transition-transform tracking-widest text-[15px]">
                                                    BAŞLAT
                                                </button>
                                            ) : (
                                                <>
                                                    <button onClick={handleAccept} disabled={!liveHighestBidId || loading} className="w-full py-3.5 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:bg-neutral-800 rounded-xl font-black text-white shadow-lg active:scale-95 transition-all tracking-widest text-[15px]">
                                                        {loading ? "BEKLEYİN..." : "KABUL ET VE SAT"}
                                                    </button>
                                                    <div className="flex gap-2">
                                                        <button onClick={handleReject} disabled={!liveHighestBidId} className="flex-[1] py-2.5 bg-red-500/15 border border-red-500/30 text-red-400 font-bold rounded-xl hover:bg-red-500/25 transition-colors disabled:opacity-30 text-sm">Reddet</button>
                                                        <button onClick={handleStopAuction} className="flex-[1] py-2.5 bg-orange-500/15 border border-orange-500/30 text-orange-400 font-bold rounded-xl hover:bg-orange-500/25 transition-colors text-sm">Durdur</button>
                                                        {isQuickLive && (
                                                            <button onClick={handleResetAuction} className="flex-[1] py-2.5 bg-blue-500/15 border border-blue-500/30 text-blue-400 font-bold rounded-xl hover:bg-blue-500/25 transition-colors text-sm">Sıfırla</button>
                                                        )}
                                                    </div>
                                                </>
                                            )}
                                        </div>
                                    ) : (
                                        // İzleyici Bidding Area inside the Card
                                        <>
                                            {auctionResult ? (
                                                <div className="w-full py-3.5 bg-emerald-500/20 text-emerald-400 font-black text-center rounded-xl border border-emerald-500/30">BU ÜRÜN SATILDI</div>
                                            ) : auctionStatus === "ACTIVE" ? (
                                                <BidMiniForm adId={adId} currentHighest={liveHighestBid} minStep={minBidStep} startingBid={startingBid} />
                                            ) : (
                                                <div className="w-full py-3.5 bg-white/5 text-white/30 font-bold text-center rounded-xl border border-white/10">BEKLENİYOR</div>
                                            )}
                                        </>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* EN ALT: Sohbet Input Alanı */}
                    <div className="w-full mt-3 pointer-events-auto relative z-30">
                        <form onSubmit={(e) => { e.preventDefault(); if (message.trim()) { send(message); setMessage(""); } }} className="flex items-center gap-2 bg-black/50 backdrop-blur-xl border border-white/10 rounded-full p-1.5 pl-5 shadow-[0_5px_25px_rgba(0,0,0,0.5)] focus-within:border-emerald-500/50 focus-within:bg-black/70 transition-all w-full md:w-[400px]">
                            <input
                                type="text"
                                value={message}
                                onChange={(e) => setMessage(e.target.value)}
                                placeholder="Sohbete katıl..."
                                className="bg-transparent border-none outline-none text-white text-[15px] flex-1 placeholder-white/40 min-w-0"
                            />
                            <button type="submit" disabled={!message.trim()} className="w-10 h-10 shrink-0 rounded-full bg-emerald-500 disabled:bg-white/10 disabled:text-white/30 flex items-center justify-center text-black transition-transform active:scale-90">
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" className="ml-0.5"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
                            </button>
                        </form>
                    </div>

                </div>
            )}

            {/* ====================================================
                4. KATMAN: DEV EKRAN BİLDİRİMLERİ (Örn: Geri Sayım, Satıldı)
            ==================================================== */}
            <div className="absolute inset-0 pointer-events-none z-[100] flex items-center justify-center">
                {countdown > 0 && (
                    <div className={`w-32 h-32 flex items-center justify-center rounded-full text-white font-black text-6xl shadow-2xl ${countdown <= 10 ? 'bg-red-500/90 animate-pulse shadow-[0_0_50px_rgba(239,68,68,0.6)]' : 'bg-orange-500/90 shadow-[0_0_50px_rgba(245,158,11,0.6)]'}`}>
                        {countdown}
                    </div>
                )}

                {auctionNotification && (
                    <div className="absolute inset-0 flex items-center justify-center bg-black/30 backdrop-blur-sm z-[160] animate-[zoomFadeOut_4s_ease-in-out_forwards]">
                        <div className={`text-white px-10 py-6 rounded-[2rem] font-black text-3xl md:text-4xl text-center shadow-[0_20px_50px_rgba(0,0,0,0.5)] border-4 border-white/20 ${auctionNotification.includes("BAŞLADI") ? "bg-gradient-to-br from-emerald-500 to-emerald-700" : "bg-gradient-to-br from-orange-500 to-orange-700"}`}>
                            {auctionNotification}
                        </div>
                    </div>
                )}

                {/* Finalized Transient Overlay */}
                {showFinalization && (
                    <div className="absolute inset-0 flex items-center justify-center z-[150] bg-black/60 backdrop-blur-sm transition-all">
                        <div className="flex flex-col items-center bg-gradient-to-tr from-yellow-600/30 to-yellow-400/30 px-10 py-12 rounded-[3rem] border border-yellow-500/50 shadow-[0_0_80px_rgba(234,179,8,0.4)] animate-[pulse_2s_ease-in-out_infinite]">
                            <span className="text-7xl mb-4 drop-shadow-lg">🎉</span>
                            <h2 className="text-5xl font-black text-transparent bg-clip-text bg-gradient-to-r from-yellow-300 to-yellow-500 tracking-widest mb-2 drop-shadow-md">SATILDI!</h2>
                            <p className="text-2xl text-white font-bold mb-4">{finalizedWinner}</p>
                            <p className="text-4xl text-emerald-400 font-extrabold drop-shadow-[0_0_15px_rgba(52,211,153,0.5)]">
                                {new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(finalizedAmount || 0)}
                            </p>
                        </div>
                    </div>
                )}

                {/* Permanent Sold Overlay */}
                {auctionResult && showSoldOverlay && (
                    <div className="absolute inset-0 flex flex-col items-center justify-center z-[200] bg-black/80 backdrop-blur-lg pointer-events-auto">
                        <div className="flex flex-col items-center gap-6 px-10 py-12 rounded-[3rem] border border-yellow-500/30 bg-gradient-to-b from-neutral-900/80 to-black shadow-[0_0_100px_rgba(234,179,8,0.2)]">
                            <span className="text-[6rem] drop-shadow-[0_0_30px_rgba(255,215,0,0.8)] animate-pulse">🏆</span>
                            <h1 className="text-6xl md:text-7xl font-black tracking-widest text-transparent bg-clip-text bg-gradient-to-r from-yellow-200 via-yellow-400 to-yellow-200 animate-pulse">SATILDI</h1>

                            <div className="flex flex-col items-center gap-2 mt-2 text-center">
                                <p className="text-white/60 text-xs font-bold tracking-widest uppercase">KAZANAN</p>
                                <p className="text-white text-3xl font-black">{auctionResult.winnerName}</p>
                                <div className="mt-3 px-8 py-3 rounded-2xl font-black text-4xl bg-gradient-to-br from-emerald-500 to-emerald-700 text-white shadow-[0_0_30px_rgba(16,185,129,0.4)] border border-emerald-400/50">
                                    {formattedPrice(auctionResult.price)}
                                </div>
                                <button onClick={() => setShowSoldOverlay(false)} className="mt-8 px-8 py-3.5 rounded-full font-bold text-white bg-white/10 hover:bg-white/20 border border-white/20 transition-all text-sm tracking-wide">
                                    Ekrana Dön
                                </button>
                            </div>
                        </div>
                    </div>
                )}
            </div>

        </div>
    );
}

// MİNİMALİZE EDİLMİŞ OVERLAY İZLEYİCİ TEKLİF FORMU
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
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ roomId: adId, amount: (currentHighest || startingBid || 0) + val }),
            });
            const data = await res.json();
            if (!res.ok) alert(data.error || data.message || "Teklif verilemedi.");
            else router.refresh();
        } catch (e) { alert("Bir hata oluştu."); }
        setLoading(false);
    };

    const handleCustomBid = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount || !session?.user?.id) return;
        const rawAmount = parseInt(amount.replace(/\./g, ""), 10);
        if (rawAmount <= (currentHighest || 0)) { alert("Teklif yüksek olmalıdır."); return; }
        setLoading(true);
        try {
            const res = await fetch("/api/livekit/bid", {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ roomId: adId, amount: rawAmount }),
            });
            if (res.ok) { setAmount(""); router.refresh(); }
            else { const d = await res.json(); alert(d.error || d.message || "Hata"); }
        } catch (e) { } finally { setLoading(false); }
    };

    return (
        <div className="flex flex-col gap-2 w-full">
            {/* Hızlı Teklif Butonları */}
            <div className="flex gap-2 w-full">
                {[50, 100, 500].map(val => (
                    <button key={val} type="button" disabled={loading} onClick={() => handleQuickBid(val)} className="flex-1 py-2.5 rounded-xl bg-white/10 hover:bg-white/20 active:bg-white/30 border border-white/10 text-white font-bold text-sm transition-all disabled:opacity-50">
                        +{val}₺
                    </button>
                ))}
            </div>

            {/* Özel Teklif */}
            <form onSubmit={handleCustomBid} className="flex gap-2 w-full mt-1">
                <input
                    type="text"
                    value={amount}
                    onChange={(e) => {
                        const val = e.target.value.replace(/[^0-9]/g, "");
                        setAmount(val ? new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)) : "");
                    }}
                    className="flex-[3] min-w-0 bg-black/50 border border-white/10 focus:border-emerald-500 rounded-xl px-3 text-white text-center font-bold text-[15px] outline-none transition-colors placeholder-white/30"
                    placeholder="Özel tutar..."
                />
                <button type="submit" disabled={loading || !amount} className="flex-[2] py-2.5 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:bg-neutral-800 text-white rounded-xl font-bold tracking-wide transition-transform active:scale-95 text-sm">
                    {loading ? "..." : "TEKLİF"}
                </button>
            </form>
            <div className="text-center text-[10px] text-white/30 font-medium mt-1">Minimum Artırım: {minStep} ₺</div>
        </div>
    );
}

// CoHost Davet Popup'ı
function CoHostListener({ setRole, setWantsToPublish }: { setRole: any, setWantsToPublish: any }) {
    const [inviteVisible, setInviteVisible] = useState(false);
    const room = useRoomContext();

    useDataChannel((msg) => {
        try {
            const dataObj = JSON.parse(new TextDecoder().decode(msg.payload));
            if (dataObj.type === "INVITE_TO_STAGE") setInviteVisible(true);
            else if (dataObj.type === "KICK_FROM_STAGE") {
                setWantsToPublish(false); setRole("viewer"); alert("Sahneden alındınız."); room.disconnect();
            }
        } catch (e) { }
    });

    if (!inviteVisible) return null;

    return (
        <div className="absolute inset-0 bg-black/80 backdrop-blur-md flex justify-center items-center z-[9999]">
            <div className="bg-neutral-900 p-8 rounded-3xl max-w-sm text-center border border-white/10 shadow-2xl animate-[fadeInUp_0.4s_ease-out_forwards]">
                <div className="text-5xl mb-4">🎤</div>
                <h3 className="text-white text-xl font-black mb-2">Sahneye Davet!</h3>
                <p className="text-white/70 text-sm mb-6">Yayıncı sizinle beraber yayına katılmanızı istiyor. <b>Kameranız açılacaktır.</b></p>
                <div className="flex gap-3 justify-center">
                    <button onClick={() => setInviteVisible(false)} className="px-6 py-2.5 rounded-full bg-white/5 hover:bg-white/10 border border-white/10 text-white font-bold transition-all">Reddet</button>
                    <button onClick={async () => { setInviteVisible(false); await room.disconnect(); setRole("guest"); }} className="px-6 py-2.5 rounded-full bg-blue-600 hover:bg-blue-500 text-white font-bold shadow-[0_0_15px_rgba(37,99,235,0.4)] transition-all">Kabul Et</button>
                </div>
            </div>
        </div>
    );
}