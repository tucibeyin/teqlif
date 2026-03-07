"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer } from "@livekit/components-react";
import "@livekit/components-styles";
import { useSession } from "next-auth/react";
import { CustomArenaLayout } from "@/app/ad/[id]/arena/CustomArenaLayout";

interface Props {
    hostId: string;
    hostName: string;
    isOwner: boolean;
}

export default function ChannelArena({ hostId, hostName, isOwner }: Props) {
    const { data: session } = useSession();
    const [token, setToken] = useState("");
    const [wantsToPublish] = useState(isOwner);

    const roomName = `channel:${hostId}`;

    const fetchToken = useCallback(async () => {
        try {
            const resp = await fetch(
                `/api/livekit/token?room=${encodeURIComponent(roomName)}${isOwner ? "" : ""}`
            );
            const data = await resp.json();
            if (data.token) setToken(data.token);
        } catch (e) {
            console.error("[ChannelArena] Token fetch error:", e);
        }
    }, [roomName, isOwner]);

    useEffect(() => {
        if (!session?.user?.id) return;
        fetchToken();
    }, [session, fetchToken]);

    if (!token) {
        return (
            <div style={{
                padding: "2rem",
                textAlign: "center",
                background: "var(--bg-secondary)",
                borderRadius: "var(--radius-lg)",
            }}>
                <p>Kanala bağlanılıyor...</p>
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
                adId=""
                sellerId={hostId}
                isOwner={isOwner}
                buyItNowPrice={null}
                startingBid={0}
                minBidStep={1}
                initialHighestBid={0}
                initialIsAuctionActive={false}
                role={isOwner ? "host" : "viewer"}
                wantsToPublish={wantsToPublish}
                adOwnerName={hostName}
                isQuickLive={true}
            />
            <RoomAudioRenderer />
        </LiveKitRoom>
    );
}
