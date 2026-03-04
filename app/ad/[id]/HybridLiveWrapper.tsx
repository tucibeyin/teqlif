"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom } from "@livekit/components-react";
import { useSession } from "next-auth/react";

interface HybridLiveWrapperProps {
    roomId: string;
    isOwner: boolean;
    children: React.ReactNode;
}

export default function HybridLiveWrapper({ roomId, isOwner, children }: HybridLiveWrapperProps) {
    const { data: session } = useSession();
    const [token, setToken] = useState("");
    const role = isOwner ? "host" : "viewer";

    const fetchToken = useCallback(async () => {
        try {
            const resp = await fetch(`/api/livekit/token?room=${roomId}&role=${role}`);
            const data = await resp.json();
            setToken(data.token);
        } catch (e) {
            console.error("LiveKit token hatası:", e);
        }
    }, [roomId, role]);

    useEffect(() => {
        if (!session?.user?.id) return;
        fetchToken();
    }, [roomId, session, fetchToken]);

    if (!token) {
        return (
            <div className="w-full h-full flex items-center justify-center p-8 bg-gray-50 rounded-xl">
                <div className="flex flex-col items-center gap-4">
                    <div className="w-8 h-8 rounded-full border-4 border-red-500 border-t-transparent animate-spin"></div>
                    <p className="text-gray-500 font-medium">Canlı yayına bağlanılıyor...</p>
                </div>
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
            connect={true}
            className="w-full h-full"
            onDisconnected={() => {
                // When we disconnect or are kicked/closed, force a refresh so the UI resets to static ad data 
                window.location.reload();
            }}
        >
            {children}
        </LiveKitRoom>
    );
}
