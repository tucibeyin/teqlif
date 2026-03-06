"use client";

import { useEffect, useRef, useState } from "react";
import type { AuctionStatus } from "../types";

const T = {
  glass: "rgba(255,255,255,0.04)",
  glassBorder: "rgba(255,255,255,0.07)",
  teal: "#06C8E0",
  gold: "#F0B429",
  green: "#10D88A",
  text: "#EDF2F7",
  muted: "#3D526A",
  mono: "'DM Mono', monospace",
  display: "'Syne', system-ui, sans-serif",
};

function BidFlash({ amount }: { amount: number }) {
  const [flash, setFlash] = useState(false);
  const prev = useRef(amount);
  useEffect(() => {
    if (prev.current !== amount) {
      setFlash(true);
      const t = setTimeout(() => setFlash(false), 700);
      prev.current = amount;
      return () => clearTimeout(t);
    }
  }, [amount]);
  return (
    <span style={{
      fontFamily: T.mono, fontSize: "2.1rem", fontWeight: 500,
      letterSpacing: -1.5, transition: "color 0.45s ease, text-shadow 0.45s ease",
      color: flash ? T.green : T.gold,
      textShadow: flash ? `0 0 20px rgba(16,216,138,0.5)` : `0 0 20px rgba(240,180,41,0.25)`,
    }}>
      {new Intl.NumberFormat("tr-TR").format(amount)} ₺
    </span>
  );
}

const AVATAR_COLORS = ["#06C8E0", "#F03E3E", "#F0B429", "#10D88A", "#8B5CF6", "#F97316"];

interface StatsBarProps {
  auctionStatus: AuctionStatus;
  highestBid: number;
  startingBid?: number | null;
  buyItNowPrice?: number | null;
  highestBidderName?: string | null;
  flashBid: boolean;
  notification?: string | null;
}

export function StatsBar({
  auctionStatus, highestBid, startingBid,
  buyItNowPrice, highestBidderName, notification,
}: StatsBarProps) {
  const displayPrice = highestBid > 0 ? highestBid : (startingBid ?? 0);
  const isActive = auctionStatus === "ACTIVE";
  const bidderColor = highestBidderName
    ? AVATAR_COLORS[highestBidderName.charCodeAt(0) % AVATAR_COLORS.length]
    : T.muted;

  return (
    <>
      <style>{`
        @keyframes tq-fadeInDown {
          from { opacity: 0; transform: translateY(-8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        @keyframes tq-activePulse {
          0%, 100% { box-shadow: 0 0 0 0 rgba(16,216,138,0.15); }
          50%       { box-shadow: 0 0 0 4px rgba(16,216,138,0); }
        }
      `}</style>

      {notification && (
        <div style={{
          background: "rgba(6,200,224,0.1)", border: "1px solid rgba(6,200,224,0.22)",
          borderRadius: 10, padding: "7px 14px", marginBottom: 8,
          color: T.teal, fontWeight: 700, fontSize: "0.75rem",
          textAlign: "center", letterSpacing: 0.8, fontFamily: T.display,
          animation: "tq-fadeInDown 0.3s ease-out",
        }}>
          {notification}
        </div>
      )}

      <div
        id="arena-stats-bar"
        style={{
          background: "rgba(6,8,16,0.82)", backdropFilter: "blur(24px)",
          WebkitBackdropFilter: "blur(24px)", borderRadius: 14,
          border: isActive
            ? "1px solid rgba(16,216,138,0.28)"
            : "1px solid rgba(255,255,255,0.08)",
          padding: "10px 14px",
          display: "flex", justifyContent: "space-between", alignItems: "flex-end",
          transition: "border-color 0.5s, box-shadow 0.5s",
          boxShadow: isActive
            ? "0 0 24px rgba(16,216,138,0.07)"
            : "none",
          animation: isActive ? "tq-activePulse 2.5s ease infinite" : "none",
        }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
          {/* Status label */}
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            {isActive && (
              <span style={{
                width: 6, height: 6, borderRadius: "50%",
                background: T.green,
                boxShadow: "0 0 6px rgba(16,216,138,0.7)",
                display: "inline-block", flexShrink: 0,
              }} />
            )}
            <span style={{
              fontSize: "0.58rem", fontFamily: T.mono, color: T.muted,
              letterSpacing: 2, textTransform: "uppercase",
            }}>
              {isActive ? "EN YÜKSEK TEKLİF" : "BAŞLANGIÇ FİYATI"}
            </span>
          </div>

          <BidFlash amount={displayPrice} />

          {/* Bidder */}
          {highestBidderName && (
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <div style={{
                width: 16, height: 16, borderRadius: "50%", flexShrink: 0,
                background: bidderColor,
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 8, fontWeight: 900, color: "white", fontFamily: T.display,
              }}>
                {highestBidderName.charAt(0).toUpperCase()}
              </div>
              <span style={{
                fontSize: "0.72rem", color: bidderColor,
                fontFamily: T.display, fontWeight: 600,
              }}>
                {highestBidderName}
              </span>
            </div>
          )}
        </div>

        {/* Buy it now */}
        {buyItNowPrice && (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 3 }}>
            <span style={{
              fontSize: "0.58rem", fontFamily: T.mono, color: T.muted,
              letterSpacing: 2, textTransform: "uppercase",
            }}>
              HEMEN AL
            </span>
            <span style={{
              fontFamily: T.mono, fontSize: "1.05rem", fontWeight: 500, color: T.teal,
            }}>
              {new Intl.NumberFormat("tr-TR").format(buyItNowPrice)} ₺
            </span>
          </div>
        )}
      </div>
    </>
  );
}
