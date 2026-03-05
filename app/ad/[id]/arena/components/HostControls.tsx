"use client";

import { TrackToggle, useRoomContext } from "@livekit/components-react";
import { Track } from "livekit-client";
import type { AuctionStatus } from "../types";

const T = {
  teal: "#00B4CC",
  green: "#00E096",
  red: "#FF4757",
  glass: "rgba(255,255,255,0.06)",
  glassBorder: "rgba(255,255,255,0.08)",
  text: "#E8EFF7",
  display: "'Syne', system-ui, sans-serif",
};

const ROUND: React.CSSProperties = {
  width: 44, height: 44, borderRadius: "50%",
  background: T.glass, border: `1px solid ${T.glassBorder}`,
  fontSize: 18, cursor: "pointer", color: T.text,
  display: "flex", alignItems: "center", justifyContent: "center",
  transition: "all 0.15s", backdropFilter: "blur(12px)",
};

const TRACK_STYLE: React.CSSProperties = {
  ...ROUND,
  border: `1px solid ${T.glassBorder}`,
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
  auctionStatus, onStartAuction, onStopAuction, onResetAuction,
  onEndBroadcast, stageRequestCount, onStageRequestClick, loading,
}: HostControlsProps) {
  const room = useRoomContext();

  const handleCameraSwitch = async () => {
    try {
      const pubs = Array.from(room.localParticipant.videoTrackPublications.values());
      const vid = pubs.find(p => p.source === Track.Source.Camera);
      // @ts-ignore
      if (vid?.videoTrack) await vid.videoTrack.switchCamera();
    } catch (e) { console.error("Kamera değiştirme hatası:", e); }
  };

  const isActive = auctionStatus === "ACTIVE";

  return (
    <>
      <style>{`
        @keyframes tq-pulse {
          0%, 100% { box-shadow: 0 0 0 0 rgba(59,130,246,0.5); }
          50%       { box-shadow: 0 0 0 8px rgba(59,130,246,0); }
        }
        .tq-round-btn:hover { background: rgba(255,255,255,0.12) !important; }
      `}</style>

      <div style={{
        position: "absolute", bottom: 20, left: "50%",
        transform: "translateX(-50%)", zIndex: 200,
        display: "flex", flexDirection: "row",
        alignItems: "center", gap: 10,
        background: "rgba(7,11,15,0.7)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        borderRadius: 100, padding: "8px 20px",
        border: `1px solid ${T.glassBorder}`,
        pointerEvents: "auto",
      }}>

        {/* Mic toggle */}
        <TrackToggle
          source={Track.Source.Microphone}
          style={TRACK_STYLE}
          className="backdrop-blur-lg"
        />

        {/* Camera toggle */}
        <TrackToggle
          source={Track.Source.Camera}
          style={TRACK_STYLE}
          className="backdrop-blur-lg"
        />

        {/* Flip camera */}
        <button className="tq-round-btn" onClick={handleCameraSwitch} style={ROUND} title="Kamera Değiştir">
          🔄
        </button>

        {/* Divider */}
        <div style={{ width: 1, height: 24, background: T.glassBorder }} />

        {/* Reset */}
        <button
          className="tq-round-btn"
          onClick={onResetAuction}
          disabled={loading}
          style={{ ...ROUND, background: "rgba(245,158,11,0.1)", border: "1px solid rgba(245,158,11,0.2)" }}
          title="Sıfırla"
        >
          ↺
        </button>

        {/* Auction toggle */}
        <button
          onClick={isActive ? onStopAuction : onStartAuction}
          disabled={loading}
          style={{
            padding: "8px 18px", borderRadius: 100, cursor: "pointer",
            fontFamily: T.display, fontSize: 12, fontWeight: 800,
            letterSpacing: 0.5, transition: "all 0.2s",
            background: isActive ? "rgba(255,71,87,0.15)" : "rgba(0,224,150,0.15)",
            border: `1px solid ${isActive ? "rgba(255,71,87,0.3)" : "rgba(0,224,150,0.3)"}`,
            color: isActive ? T.red : T.green,
          }}
        >
          {isActive ? "⏹ Durdur" : "▶ Başlat"}
        </button>

        {/* Stage requests */}
        {stageRequestCount > 0 && (
          <div style={{ position: "relative" }}>
            <button
              onClick={onStageRequestClick}
              style={{
                ...ROUND,
                background: "rgba(59,130,246,0.15)",
                border: "2px solid rgba(59,130,246,0.4)",
                animation: "tq-pulse 1.5s infinite",
              }}
            >
              🎤
            </button>
            <span style={{
              position: "absolute", top: -5, right: -5,
              background: T.red, color: "white", fontSize: 10,
              fontWeight: 800, padding: "2px 6px", borderRadius: 10,
              fontFamily: T.display,
            }}>
              {stageRequestCount}
            </span>
          </div>
        )}

        {/* Divider */}
        <div style={{ width: 1, height: 24, background: T.glassBorder }} />

        {/* End broadcast */}
        <button
          onClick={onEndBroadcast}
          style={{
            ...ROUND,
            background: "rgba(255,71,87,0.1)",
            border: "1px solid rgba(255,71,87,0.25)",
            color: T.red,
          }}
          title="Yayını Bitir"
          onMouseOver={e => (e.currentTarget.style.background = "rgba(255,71,87,0.25)")}
          onMouseOut={e => (e.currentTarget.style.background = "rgba(255,71,87,0.1)")}
        >
          ✕
        </button>
      </div>
    </>
  );
}
