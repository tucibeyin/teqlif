"use client";

import { useState } from "react";
import { TrackToggle, useRoomContext } from "@livekit/components-react";
import { Track } from "livekit-client";
import type { AuctionStatus } from "../types";
import { PinItemModal } from "./PinItemModal";
import type { PinPayload } from "./PinItemModal";

const T = {
  glass: "rgba(255,255,255,0.06)",
  glassBorder: "rgba(255,255,255,0.09)",
  green: "#10D88A",
  red: "#F03E3E",
  gold: "#F0B429",
  text: "#EDF2F7",
  display: "'Syne', system-ui, sans-serif",
};

// Base FAB style — 48x48 round cam-glass button
const FAB: React.CSSProperties = {
  width: 48, height: 48, borderRadius: "50%",
  background: "rgba(14,20,34,0.75)",
  border: `1px solid ${T.glassBorder}`,
  backdropFilter: "blur(16px)", WebkitBackdropFilter: "blur(16px)",
  fontSize: 18, cursor: "pointer", color: T.text,
  display: "flex", alignItems: "center", justifyContent: "center",
  transition: "all 0.18s", boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
};

export interface HostControlsProps {
  auctionStatus: AuctionStatus;
  onStartAuction: () => void;
  onStopAuction: () => void;
  onResetAuction: () => void;
  onEndBroadcast: () => void;
  stageRequestCount: number;
  onStageRequestClick: () => void;
  onInviteClick: () => void;
  loading: boolean;
  /** Kanal modunda ürün sabitleme. Verilmezse Pin butonu gösterilmez. */
  onPinItem?: (payload: PinPayload) => Promise<void>;
}

export function HostControls({
  auctionStatus, onStartAuction, onStopAuction, onResetAuction,
  onEndBroadcast, stageRequestCount, onStageRequestClick, onInviteClick, loading,
  onPinItem,
}: HostControlsProps) {
  const room = useRoomContext();
  const isActive = auctionStatus === "ACTIVE";

  const [showPinModal, setShowPinModal] = useState(false);

  const handleCameraSwitch = async () => {
    try {
      const pubs = Array.from(room.localParticipant.videoTrackPublications.values());
      const vid = pubs.find(p => p.source === Track.Source.Camera);
      // @ts-ignore
      if (vid?.videoTrack) await vid.videoTrack.switchCamera();
    } catch (e) { console.error("Kamera değiştirme hatası:", e); }
  };

  return (
    <>
      <style>{`
        @keyframes tq-stagePulse {
          0%, 100% { box-shadow: 0 0 0 0 rgba(99,102,241,0.6), 0 4px 16px rgba(0,0,0,0.4); }
          50%       { box-shadow: 0 0 0 10px rgba(99,102,241,0), 0 4px 16px rgba(0,0,0,0.4); }
        }
        .tq-fab:hover { background: rgba(255,255,255,0.12) !important; transform: scale(1.06); }
        .tq-fab:active { transform: scale(0.95); }
        .tq-fab-lk button {
          width: 48px !important; height: 48px !important;
          border-radius: 50% !important;
          background: rgba(14,20,34,0.75) !important;
          border: 1px solid rgba(255,255,255,0.09) !important;
          backdrop-filter: blur(16px) !important;
          font-size: 18px !important; color: #EDF2F7 !important;
          box-shadow: 0 4px 16px rgba(0,0,0,0.4) !important;
          transition: all 0.18s !important;
          cursor: pointer;
        }
        .tq-fab-lk button:hover { background: rgba(255,255,255,0.12) !important; transform: scale(1.06); }
        .tq-fab-lk button[data-lk-enabled="false"] { opacity: 0.55; }
      `}</style>

      {/* ── MEDIA FABs — bottom left ───────────────────────────────── */}
      <div style={{
        position: "absolute", bottom: 24, left: 20, zIndex: 200,
        display: "flex", flexDirection: "row", gap: 10,
        pointerEvents: "auto",
      }}>
        <TrackToggle
          source={Track.Source.Microphone}
          className="tq-fab-lk"
        />
        <TrackToggle
          source={Track.Source.Camera}
          className="tq-fab-lk"
        />
        <button
          className="tq-fab"
          onClick={onInviteClick}
          style={FAB}
          title="Sahneye Davet Et"
        >
          🎤
        </button>
        <button
          className="tq-fab"
          onClick={handleCameraSwitch}
          style={FAB}
          title="Kamerayı Çevir"
        >
          🔄
        </button>
      </div>

      {/* ── AUCTION FABs — bottom center ──────────────────────────── */}
      <div style={{
        position: "absolute", bottom: 24, left: "50%",
        transform: "translateX(-50%)", zIndex: 200,
        display: "flex", flexDirection: "row", alignItems: "center", gap: 10,
        pointerEvents: "auto",
      }}>
        {/* Reset — small FAB */}
        <button
          className="tq-fab"
          onClick={onResetAuction}
          disabled={loading}
          title="Sıfırla"
          style={{
            ...FAB,
            width: 40, height: 40,
            background: "rgba(240,180,41,0.1)",
            border: "1px solid rgba(240,180,41,0.22)",
            color: T.gold, fontSize: 20,
            opacity: loading ? 0.5 : 1,
          }}
        >
          ↺
        </button>

        {/* Start / Stop — large pill FAB */}
        <button
          onClick={isActive ? onStopAuction : onStartAuction}
          disabled={loading}
          style={{
            height: 48, padding: "0 26px", borderRadius: 100,
            cursor: loading ? "not-allowed" : "pointer",
            fontFamily: T.display, fontSize: 13, fontWeight: 900,
            letterSpacing: 1, transition: "all 0.22s",
            backdropFilter: "blur(16px)", WebkitBackdropFilter: "blur(16px)",
            boxShadow: isActive
              ? "0 0 24px rgba(240,62,62,0.3), 0 4px 16px rgba(0,0,0,0.4)"
              : "0 0 24px rgba(16,216,138,0.25), 0 4px 16px rgba(0,0,0,0.4)",
            background: isActive
              ? "linear-gradient(135deg, rgba(240,62,62,0.25), rgba(200,30,30,0.2))"
              : "linear-gradient(135deg, rgba(16,216,138,0.22), rgba(10,160,100,0.18))",
            border: isActive
              ? "1px solid rgba(240,62,62,0.4)"
              : "1px solid rgba(16,216,138,0.38)",
            color: isActive ? T.red : T.green,
            opacity: loading ? 0.6 : 1,
          }}
        >
          {isActive ? "⏹ Durdur" : "▶ Başlat"}
        </button>
      </div>

      {/* ── PIN ITEM FAB — bottom right (kanal modu) ───────────────── */}
      {onPinItem && (
        <div style={{
          position: "absolute", bottom: 24, right: 20, zIndex: 200,
          pointerEvents: "auto",
        }}>
          <button
            className="tq-fab"
            onClick={() => setShowPinModal(true)}
            title="Ürün Sabitle"
            style={{
              ...FAB,
              background: showPinModal ? "rgba(6,200,224,0.2)" : FAB.background,
              border: showPinModal ? "1px solid rgba(6,200,224,0.4)" : FAB.border,
            }}
          >
            📌
          </button>
        </div>
      )}

      {/* ── STAGE REQUEST FAB — bottom right ──────────────────────── */}
      {stageRequestCount > 0 && (
        <div style={{
          position: "absolute", bottom: 24, right: 20, zIndex: 200,
          pointerEvents: "auto",
        }}>
          <div style={{ position: "relative" }}>
            <button
              onClick={onStageRequestClick}
              style={{
                ...FAB,
                background: "rgba(99,102,241,0.18)",
                border: "1px solid rgba(99,102,241,0.38)",
                animation: "tq-stagePulse 1.6s ease infinite",
              }}
            >
              🎤
            </button>
            <span style={{
              position: "absolute", top: -4, right: -4,
              background: T.red, color: "white",
              fontSize: 10, fontWeight: 900, fontFamily: T.display,
              padding: "2px 6px", borderRadius: 10,
              boxShadow: "0 2px 8px rgba(240,62,62,0.5)",
            }}>
              {stageRequestCount}
            </span>
          </div>
        </div>
      )}

      {/* ── PinItemModal ───────────────────────────────────────────── */}
      {onPinItem && (
        <PinItemModal
          isOpen={showPinModal}
          onClose={() => setShowPinModal(false)}
          onSubmit={onPinItem}
        />
      )}
    </>
  );
}
