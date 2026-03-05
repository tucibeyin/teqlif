"use client";

import { useState, useCallback } from "react";
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
import { FlyingEmojis, ReactionBar } from "./components/FlyingEmojis";
import { BidPanel } from "./components/BidPanel";
import { FinalizationOverlay, SoldOverlay, BroadcastEndedScreen } from "./components/Overlays";

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
    const [countdown, setCountdown] = useState(0);

    // ── Hooks ──────────────────────────────────────────────────────────────────

    const auction = useAuction({
        adId, sellerId, room,
        initialHighestBid, initialIsAuctionActive,
    });

    const chat = useArenaChat();
    const reactions = useReactions();
    const stage = useStageRequests();

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
        onNewBid:           auction.onNewBid,
        onBidAccepted:      auction.onBidAccepted,
        onBidRejected:      auction.onBidRejected,
        onChat:             chat.onChatMessage,
        onReaction:         reactions.addReaction,
        onAuctionStart:     auction.onAuctionStart,
        onAuctionEnd:       auction.onAuctionEnd,
        onAuctionReset:     auction.onAuctionReset,
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
        onRoomClosed:        () => setIsRoomClosed(true),
        onCountdown:         setCountdown,
        onStageRequest:      stage.onStageRequest,
    });

    // ── Derived ────────────────────────────────────────────────────────────────

    const isBroadcastEnded = isRoomClosed || connectionState === ConnectionState.Disconnected;
    const hostTrack = tracks[0] ?? null;
    const guestTrack = tracks.length > 1 ? tracks[1] : null;

    // ── Handlers ───────────────────────────────────────────────────────────────

    const handleEndBroadcast = async (skipConfirm = false) => {
        if (!skipConfirm && !confirm("Yayını bitirmek istiyor musunuz?")) return;
        try {
            if (room) {
                room.localParticipant.publishData(
                    new TextEncoder().encode(JSON.stringify({ type: "ROOM_CLOSED" })),
                    { reliable: true }
                );
            }
            await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isLive: false }),
            });
            room?.disconnect();
            router.refresh();
        } catch (e) {
            console.error(e);
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
        room.localParticipant.publishData(
            new TextEncoder().encode(JSON.stringify({ type: "INVITE_TO_STAGE", targetIdentity: userId })),
            { reliable: true }
        );
    };

    // ── Render ─────────────────────────────────────────────────────────────────

    return (
        <div
            className="flex flex-col md:flex-row w-full h-full overflow-hidden relative"
            style={{ background: "#060810" }}
        >
            {/* ══ VIDEO PANEL ═══════════════════════════════════════════════ */}
            <div
                className="flex-[3_3_0] min-h-0 relative overflow-hidden border-b md:border-b-0 md:border-r flex flex-col"
                style={{ borderColor: "rgba(255,255,255,0.05)", background: "#080C18" }}
            >
                <div className="w-full h-full relative overflow-hidden">
                    <div style={{ position: "absolute", inset: 0 }}>
                        {isBroadcastEnded ? (
                            <BroadcastEndedScreen />
                        ) : hostTrack ? (
                            hostTrack.publication?.isMuted ? (
                                <div className="w-full h-full flex items-center justify-center text-white"
                                    style={{ background: "#0D1220" }}>
                                    <span style={{ fontSize: "3rem" }}>📷</span>
                                </div>
                            ) : (
                                <VideoTrack
                                    trackRef={hostTrack}
                                    style={{ width: "100%", height: "100%", objectFit: "cover" }}
                                />
                            )
                        ) : (
                            <div className="w-full h-full flex flex-col items-center justify-center"
                                style={{ background: "#080C18" }}>
                                <div style={{
                                    fontSize: "2.5rem", marginBottom: 16, opacity: 0.25,
                                }}>
                                    📡
                                </div>
                                <h2 style={{
                                    fontSize: "1.05rem", fontWeight: 700,
                                    color: "rgba(255,255,255,0.35)",
                                    fontFamily: "'Syne', system-ui, sans-serif",
                                }}>
                                    Yayıncı bekleniyor...
                                </h2>
                                <p style={{
                                    opacity: 0.25, marginTop: 6, fontSize: "0.78rem",
                                    color: "white",
                                    fontFamily: "'Syne', system-ui, sans-serif",
                                }}>
                                    Açık arttırma birazdan başlayacak.
                                </p>
                            </div>
                        )}
                    </div>

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

                            {/* Stats overlay */}
                            <div style={{
                                position: "absolute", top: 90, left: 16, right: 16,
                                zIndex: 200, pointerEvents: "auto",
                            }}>
                                <StatsBar
                                    auctionStatus={auction.status}
                                    highestBid={auction.highestBid}
                                    startingBid={startingBid}
                                    buyItNowPrice={buyItNowPrice}
                                    highestBidderName={auction.highestBidderName}
                                    flashBid={auction.flashBid}
                                    notification={auction.notification}
                                />
                            </div>

                            {/* Countdown */}
                            {countdown > 0 && (
                                <div style={{
                                    position: "absolute", top: "50%", left: "50%",
                                    transform: "translate(-50%, -50%)",
                                    fontSize: "9rem", fontWeight: 900, color: "white",
                                    textShadow: "0 0 50px rgba(240,62,62,0.7)",
                                    zIndex: 150, fontFamily: "'Syne', system-ui, sans-serif",
                                }}>
                                    {countdown}
                                </div>
                            )}

                            {/* Guest PiP */}
                            {guestTrack && (
                                <div style={{
                                    position: "absolute", bottom: 100, right: 20,
                                    width: 100, height: 140, borderRadius: 14,
                                    overflow: "hidden", border: "2px solid rgba(255,255,255,0.18)",
                                    boxShadow: "0 8px 28px rgba(0,0,0,0.65)", zIndex: 10,
                                    background: "black",
                                }}>
                                    {guestTrack.publication?.isMuted ? (
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
                                    loading={auction.loading}
                                />
                            )}

                            {/* Viewer: vertical reaction bar */}
                            {!isOwner && (
                                <div style={{
                                    position: "absolute", right: 16, bottom: "50%",
                                    transform: "translateY(50%)",
                                    zIndex: 200, pointerEvents: "auto",
                                }}>
                                    <ReactionBar onReact={reactions.sendReaction} vertical={true} />
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>

            {/* ══ CONTROL PANEL ═════════════════════════════════════════════ */}
            {!isBroadcastEnded && (
                <div
                    className="w-full md:w-[340px] flex-shrink-0 flex flex-col relative z-50 h-[45vh] md:h-full"
                    style={{
                        background: "rgba(8,12,22,0.97)",
                        borderLeft: "1px solid rgba(255,255,255,0.05)",
                    }}
                >
                    {/* Sold overlay */}
                    {auction.result && auction.showSoldOverlay && (
                        <SoldOverlay
                            winnerName={auction.result.winnerName}
                            price={auction.result.price}
                            isOwner={isOwner}
                            onClose={() => auction.setShowSoldOverlay(false)}
                            onReset={isOwner ? auction.reset : undefined}
                        />
                    )}

                    {/* Finalization overlay */}
                    {auction.showFinalization && auction.finalizedWinner && (
                        <FinalizationOverlay
                            winnerName={auction.finalizedWinner}
                            amount={auction.finalizedAmount}
                            onClose={() => auction.setShowFinalization(false)}
                        />
                    )}

                    {/* Stats */}
                    <div style={{
                        padding: "16px 16px 12px",
                        borderBottom: "1px solid rgba(255,255,255,0.05)",
                    }}>
                        <StatsBar
                            auctionStatus={auction.status}
                            highestBid={auction.highestBid}
                            startingBid={startingBid}
                            buyItNowPrice={buyItNowPrice}
                            highestBidderName={auction.highestBidderName}
                            flashBid={auction.flashBid}
                            notification={auction.notification}
                        />
                    </div>

                    {/* Chat */}
                    <div style={{ flex: 1, padding: "12px 16px", overflow: "hidden" }}>
                        <ChatOverlay
                            messages={chat.messages}
                            inputValue={chat.inputValue}
                            onInputChange={chat.setInputValue}
                            onSend={chat.sendMessage}
                            currentUserId={session?.user?.id}
                            onInviteToStage={isOwner ? handleInviteFromChat : undefined}
                        />
                    </div>

                    {/* Bid panel */}
                    <div style={{
                        padding: "12px 16px",
                        borderTop: "1px solid rgba(255,255,255,0.05)",
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

                    {/* Host: reaction bar */}
                    {isOwner && (
                        <div style={{
                            padding: "10px 16px 14px",
                            borderTop: "1px solid rgba(255,255,255,0.05)",
                            display: "flex", justifyContent: "center",
                        }}>
                            <ReactionBar onReact={reactions.sendReaction} />
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}
