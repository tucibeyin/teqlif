"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer } from "@livekit/components-react";
import "@livekit/components-styles";
import { useSession } from "next-auth/react";

import { CustomArenaLayout } from "./arena/CustomArenaLayout";

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
    isQuickLive = false,
}: LiveArenaProps) {
    const { data: session } = useSession();
    const [token, setToken] = useState("");
    const [role, setRole] = useState(isOwner ? "host" : "viewer");
    const [wantsToPublish, setWantsToPublish] = useState(isOwner);

    // Kanal mimarisi: Eğer sellerId varsa (normal akış), 
    // LiveKit odası olarak 'channel:${sellerId}' kullanılır.
    const effectiveRoomId = sellerId ? `channel:${sellerId}` : roomId;

    const fetchToken = useCallback(async (currentRole: string) => {
        try {
            const resp = await fetch(
                `/api/livekit/token?room=${effectiveRoomId}${currentRole === "guest" ? "&role=guest" : ""}`
            );
            const data = await resp.json();
            setToken(data.token);
            if (currentRole === "guest") setWantsToPublish(true);
        } catch (e) {
            console.error("LiveKit token hatası:", e);
        }
    }, [effectiveRoomId]);

    useEffect(() => {
        if (!session?.user?.id) return;
        fetchToken(role);
    }, [effectiveRoomId, session, role, fetchToken]);

    // Signal backend that we are LIVE
    useEffect(() => {
        if (isOwner && adId) {
            fetch(`/api/ads/${adId}/live`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ isLive: true, liveKitRoomId: adId })
            }).catch(err => console.error("Failed to set isLive to true:", err));
        }
    }, [isOwner, adId]);

    if (!token) {
        return (
            <div style={{
                padding: "2rem",
                textAlign: "center",
                background: "var(--bg-secondary)",
                borderRadius: "var(--radius-lg)",
            }}>
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
        </LiveKitRoom>
    );
}
