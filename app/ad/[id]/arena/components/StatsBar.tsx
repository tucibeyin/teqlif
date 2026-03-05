"use client";

import { useEffect, useRef, useState } from "react";
import type { AuctionStatus } from "../types";

const T = {
  teal: "#00B4CC",
  gold: "#F5C842",
  green: "#00E096",
  glass: "rgba(255,255,255,0.04)",
  glassBorder: "rgba(255,255,255,0.07)",
  text: "#E8EFF7",
  muted: "#4A6070",
  mono: "'DM Mono', 'Fira Code', 'Courier New', monospace",
  display: "'Syne', system-ui, sans-serif",
};

function BidFlash({ amount }: { amount: number }) {
  const [flash, setFlash] = useState(false);
  const prev = useRef(amount);
  useEffect(() => {
    if (prev.current !== amount) {
      setFlash(true);
      const t = setTimeout(() => setFlash(false), 600);
      prev.current = amount;
      return () => clearTimeout(t);
    }
  }, [amount]);
  return (
    <span style={{
      fontFamily: T.mono, fontSize: "1.75rem", fontWeight: 500,
      letterSpacing: -1, transition: "color 0.4s",
      color: flash ? T.green : T.gold,
    }}>
      {new Intl.NumberFormat("tr-TR").format(amount)} ₺
    </span>
  );
}

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

  return (
    <>
      <style>{`
        @keyframes fadeInDown {
          from { opacity: 0; transform: translateY(-6px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>

      {notification && (
        <div style={{
          background: "rgba(0,180,204,0.12)", border: "1px solid rgba(0,180,204,0.25)",
          borderRadius: 10, padding: "7px 14px", marginBottom: 8,
          color: T.teal, fontWeight: 700, fontSize: "0.78rem",
          textAlign: "center", letterSpacing: 0.5, fontFamily: T.display,
          animation: "fadeInDown 0.3s ease-out",
        }}>
          {notification}
        </div>
      )}

      <div style={{
        background: T.glass, backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        borderRadius: 16, border: `1px solid ${T.glassBorder}`,
        padding: "14px 16px", display: "flex",
        justifyContent: "space-between", alignItems: "flex-end",
      }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ fontSize: "0.6rem", fontFamily: T.mono, color: T.muted, letterSpacing: 2, textTransform: "uppercase" }}>
            {auctionStatus === "ACTIVE" ? "EN YÜKSEK TEKLİF" : "BAŞLANGIÇ FİYATI"}
          </span>
          <BidFlash amount={displayPrice} />
          {highestBidderName && (
            <span style={{ fontSize: "0.7rem", color: T.muted, fontFamily: T.display }}>
              👤 {highestBidderName}
            </span>
          )}
        </div>

        {buyItNowPrice && (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 2 }}>
            <span style={{ fontSize: "0.6rem", fontFamily: T.mono, color: T.muted, letterSpacing: 2, textTransform: "uppercase" }}>
              HEMEN AL
            </span>
            <span style={{ fontFamily: T.mono, fontSize: "1rem", fontWeight: 500, color: T.teal }}>
              {new Intl.NumberFormat("tr-TR").format(buyItNowPrice)} ₺
            </span>
          </div>
        )}
      </div>
    </>
  );
}
