"use client";

import { TrackToggle } from "@livekit/components-react";
import { Track } from "livekit-client";
import { useRoomContext } from "@livekit/components-react";
import type { AuctionStatus } from "../types";

const PILL: React.CSSProperties = {
    position: "absolute",
    bottom: "20px",
    left: "50%",
    transform: "translateX(-50%)",
    zIndex: 200,
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    gap: "16px",
    background: "rgba(0,0,0,0.5)",
    backdropFilter: "blur(12px)",
    borderRadius: "100px",
    padding: "8px 24px",
    pointerEvents: "auto",
    border: "1px solid rgba(255,255,255,0.1)",
};

const ROUND_BTN: React.CSSProperties = {
    width: "48px",
    height: "48px",
    borderRadius: "50%",
    background: "rgba(0,0,0,0.4)",
    backdropFilter: "blur(12px)",
    border: "1px solid rgba(255,255,255,0.1)",
    fontSize: "20px",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    color: "white",
    cursor: "pointer",
};

const TRACK_TOGGLE_STYLE: React.CSSProperties = {
    border: "1px solid rgba(255,255,255,0.1)",
    borderRadius: "50%",
    width: "48px",
    height: "48px",
    color: "white",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
};

interface HostControlsProps {
    auctionStatus: AuctionStatus;
    onStartAuction: () => void;
    onStopAuction: () => void;
    onResetAuction: () => void;
    onEndBroadcast: () => void;
    stageRequestCount: number;
    onStageRequestClick: () => void;
    loading: boolean;
}

export function HostControls({
    auctionStatus,
    onStartAuction,
    onStopAuction,
    onResetAuction,
    onEndBroadcast,
    stageRequestCount,
    onStageRequestClick,
    loading,
}: HostControlsProps) {
    const room = useRoomContext();

    const handleCameraSwitch = async () => {
        try {
            const publications = Array.from(room.localParticipant.videoTrackPublications.values());
            const videoPub = publications.find(p => p.source === Track.Source.Camera);
            if (videoPub?.videoTrack) {
                // @ts-ignore
                await videoPub.videoTrack.switchCamera();
            }
        } catch (e) {
            console.error("Kamera değiştirme hatası:", e);
        }
    };

    return (
        <div style={PILL}>
            <TrackToggle
                source={Track.Source.Microphone}
                className="backdrop-blur-lg bg-black/40 hover:bg-black/60 transition-all shadow-lg"
                style={TRACK_TOGGLE_STYLE}
            />
            <TrackToggle
                source={Track.Source.Camera}
                className="backdrop-blur-lg bg-black/40 hover:bg-black/60 transition-all shadow-lg"
                style={TRACK_TOGGLE_STYLE}
            />

            <button onClick={handleCameraSwitch} style={ROUND_BTN} title="Kamera Değiştir">
                🔄
            </button>

            <button onClick={onResetAuction} style={{ ...ROUND_BTN, background: "rgba(245, 158, 11, 0.6)" }} title="Sıfırla">
                🔄 0
            </button>

            {/* Auction toggle */}
            <button
                onClick={auctionStatus === "ACTIVE" ? onStopAuction : onStartAuction}
                disabled={loading}
                style={{
                    ...ROUND_BTN,
                    background: auctionStatus === "ACTIVE" ? "rgba(239,68,68,0.8)" : "rgba(34,197,94,0.8)",
                    fontSize: "1rem",
                    fontWeight: 800,
                    color: "white",
                    border: "1px solid rgba(255,255,255,0.2)",
                    padding: "0 16px",
                    width: "auto",
                    borderRadius: "100px",
                }}
            >
                {auctionStatus === "ACTIVE" ? "⏹ Durdur" : "▶ Başlat"}
            </button>

            {/* Stage requests badge */}
            {stageRequestCount > 0 && (
                <div style={{ position: "relative" }}>
                    <button
                        onClick={onStageRequestClick}
                        style={{
                            ...ROUND_BTN,
                            background: "rgba(59, 130, 246, 0.8)",
                            border: "2px solid rgba(255,255,255,0.5)",
                            boxShadow: "0 0 15px rgba(59, 130, 246, 0.8)",
                            animation: "pulse 1.5s infinite",
                        }}
                    >
                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                            <path d="M12 2v20" /><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
                        </svg>
                    </button>
                    <span style={{
                        position: "absolute",
                        top: "-5px",
                        right: "-5px",
                        background: "red",
                        color: "white",
                        fontSize: "10px",
                        fontWeight: "bold",
                        padding: "2px 6px",
                        borderRadius: "10px",
                    }}>
                        {stageRequestCount}
                    </span>
                </div>
            )}

            <button
                onClick={onEndBroadcast}
                style={{ ...ROUND_BTN, background: "rgba(220,38,38,0.8)", border: "1px solid rgba(255,100,100,0.3)" }}
                title="Yayını Bitir"
            >
                ✕
            </button>
        </div>
    );
}
