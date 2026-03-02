"use client";

import { useEffect, useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer, useTracks, VideoTrack, useDataChannel, useRoomContext } from "@livekit/components-react";
import { Track } from "livekit-client";
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
            style={{ minHeight: "500px", borderRadius: "1.5rem", overflow: "hidden", position: "relative" }}
        >
            <CustomArenaLayout />
            <RoomAudioRenderer />
            {!isOwner && <CoHostListener setRole={setRole} setWantsToPublish={setWantsToPublish} />}
        </LiveKitRoom>
    );
}

function CustomArenaLayout() {
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
            <VideoTrack trackRef={hostTrack} style={{ width: "100%", height: "100%", objectFit: "cover" }} />

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
