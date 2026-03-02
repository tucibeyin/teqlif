"use client";

import { useEffect, useState } from "react";
import { LiveKitRoom, VideoConference, RoomAudioRenderer } from "@livekit/components-react";
import "@livekit/components-styles";
import { useSession } from "next-auth/react";

interface LiveArenaProps {
    roomId: string;
    adId: string;
    isOwner: boolean;
}

export default function LiveArena({ roomId, adId, isOwner }: LiveArenaProps) {
    const { data: session } = useSession();
    const [token, setToken] = useState("");

    useEffect(() => {
        if (!session?.user?.id) return;

        const fetchToken = async () => {
            try {
                const resp = await fetch(`/api/livekit/token?room=${roomId}`);
                const data = await resp.json();
                setToken(data.token);
            } catch (e) {
                console.error("LiveKit token hatası:", e);
            }
        };
        fetchToken();
    }, [roomId, session]);

    if (!token) {
        return (
            <div style={{ padding: "2rem", textAlign: "center", background: "var(--bg-secondary)", borderRadius: "var(--radius-lg)" }}>
                <p>Canlı yayına bağlanılıyor...</p>
            </div>
        );
    }

    return (
        <LiveKitRoom
            video={isOwner}
            audio={isOwner}
            token={token}
            serverUrl={process.env.NEXT_PUBLIC_LIVEKIT_URL}
            data-lk-theme="default"
            style={{ height: "400px", borderRadius: "var(--radius-lg)", overflow: "hidden" }}
        >
            <VideoConference />
            <RoomAudioRenderer />
        </LiveKitRoom>
    );
}
