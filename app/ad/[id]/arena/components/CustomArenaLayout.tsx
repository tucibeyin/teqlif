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
            particleCount: 140, spread: 75, startVelocity: 55, gravity: 0.8,
            colors: ["#FFD700", "#FFA500", "#FF6B35", "#00B4CC", "#FFFFFF", "#22c55e"],
        };
        confetti({ ...opts, origin: { x: 0.05, y: 1 }, angle: 65 });
        confetti({ ...opts, origin: { x: 0.95, y: 1 }, angle: 115 });
        setTimeout(() => {
            confetti({ ...opts, particleCount: 80, origin: { x: 0.2, y: 0.8 }, angle: 80 });
            confetti({ ...opts, particleCount: 80, origin: { x: 0.8, y: 0.8 }, angle: 100 });
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

    // ── Stage request handler ──────────────────────────────────────────────────

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
        <div className="flex flex-col md:flex-row w-full h-full overflow-hidden relative" style={{ background: "#070B0F" }}>

            {/* ── VIDEO PANEL ─────────────────────────────────────────── */}
            <div className="flex-[1_1_0] min-h-0 relative bg-black overflow-hidden border-b md:border-b-0 md:border-r border-white/10 flex flex-col">

                {/* Video track */}
                <div className="w-full h-full relative overflow-hidden bg-neutral-900">
                    <div style={{ position: "absolute", inset: 0 }}>
                        {isBroadcastEnded ? (
                            <BroadcastEndedScreen />
                        ) : hostTrack ? (
                            hostTrack.publication?.isMuted ? (
                                <div className="w-full h-full flex items-center justify-center bg-neutral-800 text-white">
                                    <span style={{ fontSize: "3rem" }}>📷</span>
                                </div>
                            ) : (
                                <VideoTrack trackRef={hostTrack} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                            )
                        ) : (
                            <div className="w-full h-full flex flex-col items-center justify-center bg-neutral-900 text-white animate-pulse">
                                <h2 className="text-xl font-bold tracking-wider text-gray-300">Yayıncı bekleniyor...</h2>
                                <p className="opacity-50 mt-2 text-sm">Lütfen ayrılmayın, açık arttırma birazdan başlayacak.</p>
                            </div>
                        )}
                    </div>

                    {/* Overlays — only while broadcast is alive */}
                    {!isBroadcastEnded && (
                        <>
                            <FlyingEmojis reactions={reactions.reactions} />

                            <TopHUD
                                adOwnerName={adOwnerName}
                                participantCount={participants.length}
                                isOwner={isOwner}
                                onClose={handleClose}
                            />

                            {/* Stats (mobile-parity overlay) */}
                            <div style={{
                                position: "absolute", top: "100px", left: "16px", right: "16px",
                                zIndex: 200, display: "flex", flexDirection: "column", gap: "8px",
                                pointerEvents: "auto",
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
                                    fontSize: "8rem", fontWeight: 900, color: "white",
                                    textShadow: "0 0 40px rgba(239,68,68,0.8)",
                                    zIndex: 150,
                                    animation: "zoomIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)",
                                }}>
                                    {countdown}
                                </div>
                            )}

                            {/* Guest PiP */}
                            {guestTrack && (
                                <div style={{
                                    position: "absolute", bottom: "100px", right: "20px",
                                    width: "100px", height: "140px", borderRadius: "12px",
                                    overflow: "hidden", border: "2px solid white",
                                    boxShadow: "0 8px 24px rgba(0,0,0,0.5)", zIndex: 10, background: "black",
                                }}>
                                    {guestTrack.publication?.isMuted ? (
                                        <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", background: "#333" }}>
                                            <span style={{ fontSize: "24px" }}>📷</span>
                                        </div>
                                    ) : (
                                        <VideoTrack trackRef={guestTrack} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                                    )}
                                </div>
                            )}

                            {/* Host Controls */}
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

                            {/* Reaction Bar (viewer) */}
                            {!isOwner && (
                                <div style={{
                                    position: "absolute", bottom: "20px", left: "16px",
                                    zIndex: 200, pointerEvents: "auto",
                                }}>
                                    <ReactionBar onReact={reactions.sendReaction} />
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>

            {/* ── CONTROL PANEL ───────────────────────────────────────── */}
            {!isBroadcastEnded && (
                <div className="w-full md:w-96 flex-shrink-0 flex flex-col relative z-50 h-[45vh] md:h-full" style={{ background: "rgba(12,18,26,0.97)", borderLeft: "1px solid rgba(255,255,255,0.07)" }}>

                    {/* Sold overlay (inside panel) */}
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

                    {/* Stats (desktop) */}
                    <div className="p-4 border-b border-white/10">
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
                    <div className="flex-1 p-4 overflow-hidden">
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
                    <div className="p-4 border-t border-white/10">
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

                    {/* Reaction bar (host side panel) */}
                    {isOwner && (
                        <div className="p-4 border-t border-white/10">
                            <ReactionBar onReact={reactions.sendReaction} />
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}
