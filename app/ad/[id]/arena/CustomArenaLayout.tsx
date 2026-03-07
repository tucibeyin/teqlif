"use client";

import React, { useState, useEffect, useCallback } from "react";
import confetti from "canvas-confetti";
import {
    useTracks, VideoTrack, useRoomContext, useParticipants, useConnectionState,
} from "@livekit/components-react";
import { Track, ConnectionState } from "livekit-client";
import { useSession } from "next-auth/react";
import { useRouter } from "next/navigation";

// Hooks
import { useAuction } from "./hooks/useAuction";
import { useArenaChat } from "./hooks/useArenaChat";
import { useReactions } from "./hooks/useReactions";
import { useStageRequests } from "./hooks/useStageRequests";
import { useArenaDataChannel } from "./hooks/useArenaDataChannel";

// Components
import { TopHUD } from "./components/TopHUD";
import { StatsBar } from "./components/StatsBar";
import { ChatOverlay } from "./components/ChatOverlay";
import { HostControls } from "./components/HostControls";
import { ParticipantsModal } from "./components/ParticipantsModal";
import { FlyingEmojis, ReactionBar } from "./components/FlyingEmojis";
import { BidPanel } from "./components/BidPanel";
import { FinalizationOverlay, SoldOverlay, BroadcastEndedScreen } from "./components/Overlays";
import { CoHostListener } from "./components/CoHostListener";

import type { CustomArenaLayoutProps } from "./types";

export function CustomArenaLayout({
    adId, sellerId, isOwner,
    buyItNowPrice, startingBid, minBidStep = 1,
    initialHighestBid = 0, initialIsAuctionActive = false,
    role, wantsToPublish, adOwnerName = "Satıcı", isQuickLive = false,
}: CustomArenaLayoutProps) {
    const room = useRoomContext();
    const router = useRouter();
    const { data: session } = useSession();
    const tracks = useTracks([Track.Source.Camera]);
    const participants = useParticipants();
    const connectionState = useConnectionState();

    const [isRoomClosed, setIsRoomClosed] = useState(false);
    const [isParticipantsModalOpen, setIsParticipantsModalOpen] = useState(false);
    const [countdown, setCountdown] = useState(0);
    const [showInviteDialog, setShowInviteDialog] = useState(false);

    // ── SYNC STATE ON JOIN ──────────────────────────────────────────────────
    useEffect(() => {
        if (!room || isOwner) return;

        const sendSyncRequest = () => {
            const payload = JSON.stringify({ type: "SYNC_STATE_REQUEST" });
            room.localParticipant.publishData(
                new TextEncoder().encode(payload),
                { reliable: true }
            );
        };

        // Delay slightly to ensure host is ready to receive
        const timer = setTimeout(sendSyncRequest, 1500);
        return () => clearTimeout(timer);
    }, [room, isOwner]);

    // ── Hooks ──────────────────────────────────────────────────────────────────

    const auction = useAuction({
        adId, sellerId, room,
        initialHighestBid, initialIsAuctionActive, isQuickLive,
    });

    const chat = useArenaChat();
    const reactions = useReactions();
    const stage = useStageRequests(adId);

    // ── Confetti ───────────────────────────────────────────────────────────────

    const fireConfetti = useCallback(() => {
        const opts = {
            particleCount: 150, spread: 80, startVelocity: 58, gravity: 0.75,
            colors: ["#F0B429", "#F03E3E", "#10D88A", "#06C8E0", "#FFFFFF", "#8B5CF6"],
        };
        confetti({ ...opts, origin: { x: 0.05, y: 1 }, angle: 65 });
        confetti({ ...opts, origin: { x: 0.95, y: 1 }, angle: 115 });
        setTimeout(() => {
            confetti({ ...opts, particleCount: 90, origin: { x: 0.2, y: 0.8 }, angle: 80 });
            confetti({ ...opts, particleCount: 90, origin: { x: 0.8, y: 0.8 }, angle: 100 });
        }, 400);
    }, []);

    // ── Data channel dispatcher ────────────────────────────────────────────────

    useArenaDataChannel({
        onNewBid: auction.onNewBid,
        onBidAccepted: auction.onBidAccepted,
        onBidRejected: auction.onBidRejected,
        onChat: chat.onChatMessage,
        onReaction: reactions.addReaction,
        onAuctionStart: auction.onAuctionStart,
        onAuctionEnd: auction.onAuctionEnd,
        onAuctionEnded: (data) => {
            auction.onAuctionEnded(data);
            fireConfetti();
            chat.addMessage({
                id: Date.now().toString(),
                text: `🎉 İhale ${new Intl.NumberFormat("tr-TR").format(data.amount)} ₺ fiyatla tamamlandı!`,
                sender: "Sistem",
            });
        },
        onAuctionReset: auction.onAuctionReset,
        onAuctionSold: (data) => {
            auction.onAuctionSold(data);
            fireConfetti();
        },
        onSaleFinalized: (data) => {
            auction.onSaleFinalized(data);
            chat.addMessage({
                id: Date.now().toString(),
                text: `🎉 Tebrikler! ${data.winnerName ?? ""} en yüksek teklifi verdi.`,
                sender: "Sistem",
            });
        },
        onSyncStateResponse: auction.onSyncStateResponse,
        onSyncStateRequest: isOwner ? auction.broadcastState : () => { },
        onRoomClosed: () => setIsRoomClosed(true),
        onCountdown: setCountdown,
        onStageRequest: stage.onStageRequest,
        onInviteToStage: (targetIdentity) => {
            if (targetIdentity === session?.user?.id) {
                setShowInviteDialog(true);
            }
        },
        onStageUpdate: () => {
            // guestTrack re-derivation is automatic via useTracks reactive updates
        },
    });

    // ── Derived ────────────────────────────────────────────────────────────────

    // isBroadcastEnded = sadece HOST kasıtlı yayını kapattığında (ROOM_CLOSED mesajı).
    // ConnectionState.Disconnected LiveKit'in initial state'i veya kısa WebRTC kesintisi olabilir;
    // bu durum için sağ paneli saklamak yerine video üzerinde bir overlay gösteriyoruz.
    const isBroadcastEnded = isRoomClosed;
    const isReconnecting =
        !isRoomClosed &&
        (connectionState === ConnectionState.Disconnected ||
            connectionState === ConnectionState.Reconnecting);

    // ── Track Extraction ──
    const hostTrack = tracks.find(t => t.participant.identity === sellerId) ?? null;

    // Evrensel misafir tespiti: useParticipants() tüm katılımcıları (yerel + uzak) reaktif verir.
    // Kriter: asıl host (sellerId) OLMAYAN ve kamerası ya da mikrofonu aktif olan ilk katılımcı.
    const guestParticipant = participants.find(p =>
        p.identity !== sellerId &&
        (p.isCameraEnabled || p.isMicrophoneEnabled)
    ) ?? null;

    // guestParticipant'ın kamera track'ini bul (muted olsa bile container gösterilir).
    const guestTrack = tracks.find(t => t.participant.identity === guestParticipant?.identity) ?? null;

    // Oturum açan kullanıcının bizzat sahne misafiri olup olmadığı.
    const isCurrentUserGuest = !!session?.user?.id && session.user.id === guestParticipant?.identity;

    // ── Handlers ───────────────────────────────────────────────────────────────

    const handleEndBroadcast = async (skipConfirm = false) => {
        if (!skipConfirm && !confirm("Yayını bitirmek istiyor musunuz?")) return;
        try {
            if (room) {
                // Notifying others first
                await room.localParticipant.publishData(
                    new TextEncoder().encode(JSON.stringify({ type: "ROOM_CLOSED" })),
                    { reliable: true }
                );
            }
            // Updating DB
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isLive: false }),
            });

            // Local state update ensures UI changes immediately even if redirect is slow
            setIsRoomClosed(true);

            if (room) {
                await room.disconnect();
            }

            // Small delay to ensure state propagates, then full refresh or redirect
            setTimeout(() => {
                window.location.href = `/ad/${adId}?closed=true`;
            }, 500);

        } catch (e) {
            console.error("End broadcast error:", e);
            // Fallback: at least try to get out
            window.location.href = `/ad/${adId}`;
        }
    };

    const handleClose = () => {
        if (isOwner) handleEndBroadcast();
        else window.location.href = "/";
    };

    const handleStageRequestClick = () => {
        const req = stage.requests[0];
        if (req) stage.acceptRequest(req);
    };

    const handleInviteFromChat = (userId: string) => {
        stage.inviteToStage(userId);
    };

    const handleKickGuest = () => {
        if (!guestTrack?.participant?.identity) return;
        stage.kickFromStage(guestTrack.participant.identity);
    };

    // ── Render ─────────────────────────────────────────────────────────────────

    return (
        <div
            id="arena-root"
            style={{
                display: "flex",
                flexDirection: "row",
                width: "100%",
                height: "100%",
                overflow: "hidden",
                background: "#060810"
            }}
        >
            {/* ══ VIDEO PANEL ═══════════════════════════════════════════════ */}
            <div
                id="arena-video-panel"
                style={{
                    flex: 1,
                    minHeight: 0,
                    position: "relative",
                    overflow: "hidden",
                    background: "#080C18"
                }}
            >
                {/* Video / idle / ended */}
                <div style={{ position: "absolute", inset: 0 }}>
                    {isBroadcastEnded ? (
                        <BroadcastEndedScreen />
                    ) : hostTrack ? (
                        hostTrack.publication?.isMuted ? (
                            <div className="w-full h-full flex items-center justify-center"
                                style={{ background: "#0D1220" }}>
                                <span style={{ fontSize: "3rem" }}>📷</span>
                            </div>
                        ) : (
                            <VideoTrack
                                trackRef={hostTrack}
                                style={{ width: "100%", height: "100%", objectFit: "contain" }}
                            />
                        )
                    ) : (
                        <div className="w-full h-full flex flex-col items-center justify-center"
                            style={{ background: "#080C18" }}>
                            <div style={{ fontSize: "2.5rem", marginBottom: 16, opacity: 0.25 }}>📡</div>
                            <h2 style={{
                                fontSize: "1.05rem", fontWeight: 700,
                                color: "rgba(255,255,255,0.35)",
                                fontFamily: "'Syne', system-ui, sans-serif",
                            }}>
                                Yayıncı bekleniyor...
                            </h2>
                            <p style={{
                                opacity: 0.25, marginTop: 6, fontSize: "0.78rem",
                                color: "white", fontFamily: "'Syne', system-ui, sans-serif",
                            }}>
                                Açık arttırma birazdan başlayacak.
                            </p>
                        </div>
                    )}
                </div>

                {/* ── RECONNECTING OVERLAY ── */}
                {isReconnecting && (
                    <div style={{
                        position: "absolute", inset: 0, zIndex: 300,
                        background: "rgba(6,8,16,0.82)",
                        backdropFilter: "blur(6px)",
                        display: "flex", flexDirection: "column",
                        alignItems: "center", justifyContent: "center",
                        gap: 12,
                        pointerEvents: "none",
                    }}>
                        <span style={{ fontSize: "2.2rem" }}>📡</span>
                        <span style={{
                            color: "rgba(255,255,255,0.65)",
                            fontFamily: "'Syne', system-ui, sans-serif",
                            fontSize: 13, fontWeight: 600, letterSpacing: 0.5,
                        }}>
                            Bağlantı yeniden kuruluyor...
                        </span>
                    </div>
                )}

                {/* ── VIDEO OVERLAYS ── */}
                {!isBroadcastEnded && (
                    <>
                        <FlyingEmojis reactions={reactions.reactions} />

                        <TopHUD
                            adOwnerName={adOwnerName}
                            participantCount={participants.length}
                            isOwner={isOwner}
                            onClose={handleClose}
                        />

                        {/* Sold overlay — video üzerinde */}
                        {auction.result && auction.showSoldOverlay && (
                            <SoldOverlay
                                winnerName={auction.result.winnerName}
                                price={auction.result.price}
                                isOwner={isOwner}
                                onClose={() => auction.setShowSoldOverlay(false)}
                                onReset={isOwner ? auction.reset : undefined}
                            />
                        )}

                        {/* Finalization overlay — video üzerinde */}
                        {auction.showFinalization && auction.finalizedWinner && (
                            <FinalizationOverlay
                                winnerName={auction.finalizedWinner}
                                amount={auction.finalizedAmount}
                                onClose={() => auction.setShowFinalization(false)}
                            />
                        )}

                        {/* Countdown */}
                        {countdown > 0 && (
                            <div style={{
                                position: "absolute", top: "50%", left: "50%",
                                transform: "translate(-50%, -50%)",
                                fontSize: "9rem", fontWeight: 900, color: "white",
                                textShadow: "0 0 50px rgba(240,62,62,0.7)",
                                zIndex: 150, fontFamily: "'Syne', system-ui, sans-serif",
                                pointerEvents: "none",
                            }}>
                                {countdown}
                            </div>
                        )}

                        {/* Guest PiP — guestParticipant varsa odadaki HERKES görür */}
                        {guestParticipant && (
                            <div style={{
                                position: "absolute", bottom: 150, right: 20,
                                width: 100, height: 140, borderRadius: 14,
                                overflow: "hidden", border: "2px solid rgba(255,255,255,0.18)",
                                boxShadow: "0 8px 28px rgba(0,0,0,0.65)", zIndex: 10,
                                background: "black",
                            }}>
                                {(!guestTrack || guestTrack.publication?.isMuted) ? (
                                    <div style={{
                                        width: "100%", height: "100%",
                                        display: "flex", alignItems: "center", justifyContent: "center",
                                        background: "#111",
                                    }}>
                                        <span style={{ fontSize: "24px" }}>📷</span>
                                    </div>
                                ) : (
                                    <VideoTrack
                                        trackRef={guestTrack}
                                        style={{ width: "100%", height: "100%", objectFit: "cover" }}
                                    />
                                )}

                                {/* Host → kick | Misafirin kendisi → sahneyi bırak | İzleyici → buton yok */}
                                {isOwner && (
                                    <button
                                        onClick={handleKickGuest}
                                        title="Sahneden Çıkar"
                                        style={{
                                            position: "absolute", top: 6, right: 6,
                                            width: 20, height: 20, borderRadius: "50%",
                                            background: "rgba(0,0,0,0.5)", color: "white",
                                            border: "none", cursor: "pointer",
                                            display: "flex", alignItems: "center", justifyContent: "center",
                                            fontSize: 10, zIndex: 20, backdropFilter: "blur(4px)"
                                        }}
                                    >
                                        ✕
                                    </button>
                                )}
                                {isCurrentUserGuest && (
                                    <button
                                        onClick={() => stage.kickFromStage(room.localParticipant.identity)}
                                        title="Sahneden Ayrıl"
                                        style={{
                                            position: "absolute", top: 6, right: 6,
                                            width: 20, height: 20, borderRadius: "50%",
                                            background: "rgba(0,0,0,0.5)", color: "white",
                                            border: "none", cursor: "pointer",
                                            display: "flex", alignItems: "center", justifyContent: "center",
                                            fontSize: 10, zIndex: 20, backdropFilter: "blur(4px)"
                                        }}
                                    >
                                        ✕
                                    </button>
                                )}
                            </div>
                        )}


                        {/* Host FABs */}
                        {isOwner && (
                            <HostControls
                                auctionStatus={auction.status}
                                onStartAuction={auction.start}
                                onStopAuction={auction.stop}
                                onResetAuction={auction.reset}
                                onEndBroadcast={() => handleEndBroadcast()}
                                stageRequestCount={stage.requests.length}
                                onStageRequestClick={handleStageRequestClick}
                                onInviteClick={() => setIsParticipantsModalOpen(true)}
                                loading={auction.loading}
                            />
                        )}

                        {!isOwner && (
                            <CoHostListener
                                adId={adId}
                                showInviteDialog={showInviteDialog}
                                onDecline={() => setShowInviteDialog(false)}
                                onCoHostStatusChange={() => {
                                    setShowInviteDialog(false);
                                }}
                            />
                        )}

                        <ParticipantsModal
                            isOpen={isParticipantsModalOpen}
                            onClose={() => setIsParticipantsModalOpen(false)}
                            participants={participants.filter(p => p.identity !== session?.user?.id) as any}
                            onInvite={handleInviteFromChat}
                        />

                        {/* Reaction bar — sağ kenar, dikey */}
                        <div style={{
                            position: "absolute", right: 16, bottom: "50%",
                            transform: "translateY(50%)",
                            zIndex: 200, pointerEvents: "auto",
                        }}>
                            <ReactionBar onReact={reactions.sendReaction} vertical={true} />
                        </div>
                    </>
                )}
            </div>

            {/* ══ RIGHT PANEL ═══════════════════════════════════════════════ */}
            {!isBroadcastEnded && (
                <div
                    id="arena-right-panel"
                    style={{
                        width: "320px",
                        flexShrink: 0,
                        display: "flex",
                        flexDirection: "column",
                        height: "100%",
                        background: "rgba(7,10,20,1)",
                        /* Masaüstü: sol kenar (video yanında) | Mobil: üst kenar (video altında) */
                        borderLeft: "2px solid rgba(6,200,224,0.18)",
                        borderTop: "2px solid rgba(6,200,224,0.18)",
                    }}
                >
                    {/* ── SOHBET header ── */}
                    <div
                        id="arena-chat-header"
                        style={{
                            padding: "12px 16px 11px",
                            borderBottom: "1px solid rgba(255,255,255,0.08)",
                            display: "flex", alignItems: "center", justifyContent: "space-between",
                            flexShrink: 0,
                            background: "rgba(255,255,255,0.02)",
                        }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                            <span style={{ fontSize: 14 }}>💬</span>
                            <span style={{
                                fontSize: 11, fontWeight: 800, letterSpacing: 2,
                                color: "rgba(255,255,255,0.65)",
                                fontFamily: "'Syne', system-ui, sans-serif",
                            }}>
                                SOHBET
                            </span>
                        </div>
                        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                            <span style={{
                                width: 6, height: 6, borderRadius: "50%", background: "#10D88A",
                                boxShadow: "0 0 6px rgba(16,216,138,0.8)", display: "inline-block",
                            }} />
                            <span style={{
                                fontSize: 9, fontWeight: 800, color: "#10D88A",
                                fontFamily: "'Syne', system-ui, sans-serif", letterSpacing: 1.8,
                            }}>
                                CANLI
                            </span>
                        </div>
                    </div>

                    <StatsBar
                        auctionStatus={auction.status}
                        highestBid={auction.highestBid}
                        startingBid={startingBid}
                        buyItNowPrice={buyItNowPrice}
                        highestBidderName={auction.highestBidderName}
                        flashBid={auction.flashBid}
                        notification={auction.notification}
                    />

                    {/* ── Chat — flex: 1 ── */}
                    <div
                        id="arena-chat-container"
                        style={{
                            flex: 1, padding: "10px 14px",
                            overflow: "hidden", minHeight: 0,
                            display: "flex", flexDirection: "column",
                        }}>
                        <ChatOverlay
                            messages={chat.messages}
                            inputValue={chat.inputValue}
                            onInputChange={chat.setInputValue}
                            onSend={chat.sendMessage}
                            currentUserId={session?.user?.id}
                            isOwner={isOwner}
                            adId={adId}
                            onInviteToStage={isOwner ? handleInviteFromChat : undefined}
                        />
                    </div>

                    {/* ── BidPanel — sabit alt ── */}
                    <div
                        id="arena-bid-panel-container"
                        style={{
                            padding: "14px 16px 18px",
                            borderTop: "1px solid rgba(255,255,255,0.08)",
                            flexShrink: 0,
                            background: "rgba(255,255,255,0.015)",
                        }}>
                        <BidPanel
                            adId={adId}
                            sellerId={sellerId}
                            currentHighest={auction.highestBid}
                            minStep={minBidStep}
                            startingBid={startingBid}
                            buyItNowPrice={buyItNowPrice}
                            isAuctionActive={auction.status === "ACTIVE"}
                            isOwner={isOwner}
                            lastAcceptedBidId={auction.lastAcceptedBidId}
                            highestBidderId={auction.highestBidderId}
                            onAccept={auction.accept}
                            onReject={auction.reject}
                            onBuyNow={auction.buyNow}
                            loading={auction.loading}
                        />
                    </div>
                </div>
            )}
        </div>
    );
}
