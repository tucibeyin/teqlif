"use client";

import { useState, useEffect } from "react";

const T = {
  glass:       "rgba(255,255,255,0.04)",
  glassBorder: "rgba(255,255,255,0.07)",
  teal:        "#06C8E0",
  tealDark:    "#059AAF",
  green:       "#10D88A",
  red:         "#F03E3E",
  text:        "#EDF2F7",
  muted:       "#3D526A",
  mono:        "'DM Mono', monospace",
  display:     "'Syne', system-ui, sans-serif",
};

const fmt = (val: number) => new Intl.NumberFormat("tr-TR").format(val) + " ₺";

interface BidPanelProps {
  adId: string;
  sellerId: string;
  currentHighest: number;
  minStep: number;
  startingBid?: number | null;
  buyItNowPrice?: number | null;
  isAuctionActive: boolean;
  isOwner: boolean;
  lastAcceptedBidId?: string | null;
  highestBidderId?: string | null;
  onAccept?: () => void;
  onReject?: () => void;
  onBuyNow?: () => void;
  loading?: boolean;
}

export function BidPanel({
  adId, sellerId, currentHighest, minStep, startingBid,
  buyItNowPrice, isAuctionActive, isOwner,
  lastAcceptedBidId, highestBidderId,
  onAccept, onReject, onBuyNow, loading = false,
}: BidPanelProps) {
  const [amount, setAmount] = useState("");
  const [bidLoading, setBidLoading] = useState(false);
  const [status, setStatus] = useState<{ type: "success" | "error"; msg: string } | null>(null);

  const nextMin = currentHighest > 0 ? currentHighest + minStep : (startingBid ?? minStep);
  const quickSteps = [minStep, minStep * 2, minStep * 5];

  useEffect(() => {
    setAmount(nextMin.toString());
  }, [nextMin]);

  const handleBid = async (e: React.FormEvent) => {
    e.preventDefault();
    const num = parseFloat(amount.replace(/\./g, "").replace(",", "."));
    if (isNaN(num) || num < nextMin) {
      setStatus({ type: "error", msg: `Min. teklif: ${fmt(nextMin)}` });
      return;
    }
    setBidLoading(true);
    try {
      const res = await fetch(`/api/ads/${adId}/bid`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ amount: num }),
      });
      const data = await res.json();
      if (res.ok) {
        setStatus({ type: "success", msg: "✅ Teklifiniz iletildi!" });
        setTimeout(() => setStatus(null), 3000);
      } else {
        setStatus({ type: "error", msg: data.error || "Hata oluştu." });
      }
    } catch {
      setStatus({ type: "error", msg: "Bağlantı hatası." });
    } finally {
      setBidLoading(false);
    }
  };

  const handleQuickBid = async (step: number) => {
    const num = currentHighest + step;
    setBidLoading(true);
    try {
      const res = await fetch(`/api/ads/${adId}/bid`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ amount: num }),
      });
      if (res.ok) {
        setStatus({ type: "success", msg: `✅ +${fmt(step)} teklif verildi!` });
        setTimeout(() => setStatus(null), 2500);
      }
    } catch { /* noop */ }
    finally { setBidLoading(false); }
  };

  return (
    <>
      <style>{`
        .tq-bid-input::placeholder { color: #3D526A; font-family: 'DM Mono', monospace; }
        .tq-bid-input:focus {
          border-color: rgba(6,200,224,0.45) !important;
          box-shadow: 0 0 0 3px rgba(6,200,224,0.08) !important;
          outline: none;
        }
        .tq-quick-btn:hover {
          border-color: rgba(6,200,224,0.35) !important;
          color: #EDF2F7 !important;
          box-shadow: 0 0 0 1px rgba(6,200,224,0.2) !important;
          background: rgba(6,200,224,0.07) !important;
        }
        .tq-quick-btn:active { transform: scale(0.96); }
        .tq-accept-btn:hover { background: rgba(16,216,138,0.22) !important; box-shadow: 0 0 16px rgba(16,216,138,0.2) !important; }
        .tq-reject-btn:hover { background: rgba(240,62,62,0.22) !important; box-shadow: 0 0 16px rgba(240,62,62,0.2) !important; }
      `}</style>

      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>

        {/* ── HOST: accept / reject ── */}
        {isOwner && lastAcceptedBidId == null && currentHighest > 0 && (
          <div style={{ display: "flex", gap: 8 }}>
            <button
              className="tq-accept-btn"
              onClick={onAccept} disabled={loading}
              style={{
                flex: 1, padding: "12px 0", borderRadius: 12, cursor: "pointer",
                background: "rgba(16,216,138,0.1)", border: "1px solid rgba(16,216,138,0.28)",
                color: T.green, fontFamily: T.display, fontWeight: 900, fontSize: 12,
                letterSpacing: 0.8, transition: "all 0.2s",
                boxShadow: "0 2px 12px rgba(16,216,138,0.1)",
              }}
            >
              ✓ Kabul Et
            </button>
            <button
              className="tq-reject-btn"
              onClick={onReject} disabled={loading}
              style={{
                flex: 1, padding: "12px 0", borderRadius: 12, cursor: "pointer",
                background: "rgba(240,62,62,0.1)", border: "1px solid rgba(240,62,62,0.28)",
                color: T.red, fontFamily: T.display, fontWeight: 900, fontSize: 12,
                letterSpacing: 0.8, transition: "all 0.2s",
                boxShadow: "0 2px 12px rgba(240,62,62,0.1)",
              }}
            >
              ✕ Reddet
            </button>
          </div>
        )}

        {/* ── VIEWER: bid form ── */}
        {!isOwner && isAuctionActive && (
          <>
            {/* Quick bid buttons */}
            <div style={{ display: "flex", gap: 6 }}>
              {quickSteps.map(step => (
                <button
                  key={step}
                  className="tq-quick-btn"
                  onClick={() => handleQuickBid(step)}
                  disabled={bidLoading}
                  style={{
                    flex: 1, padding: "9px 0",
                    background: T.glass, border: `1px solid ${T.glassBorder}`,
                    borderRadius: 10, color: T.muted, fontFamily: T.mono,
                    fontSize: 11, cursor: "pointer", transition: "all 0.15s",
                  }}
                >
                  +{new Intl.NumberFormat("tr-TR").format(step)} ₺
                </button>
              ))}
            </div>

            {/* Custom amount */}
            <form onSubmit={handleBid} style={{ display: "flex", gap: 8 }}>
              <input
                value={amount}
                onChange={e => {
                  const raw = e.target.value.replace(/\D/g, "");
                  setAmount(raw ? new Intl.NumberFormat("tr-TR").format(parseInt(raw, 10)) : "");
                }}
                className="tq-bid-input"
                placeholder={`Min. ${fmt(nextMin)}`}
                style={{
                  flex: 1, height: 46,
                  background: T.glass, border: `1px solid ${T.glassBorder}`,
                  borderRadius: 14, padding: "0 16px",
                  color: T.text, fontSize: 15, fontFamily: T.mono,
                  fontWeight: 500, transition: "border-color 0.2s, box-shadow 0.2s",
                }}
              />
              <button
                type="submit"
                disabled={bidLoading || !amount}
                style={{
                  padding: "0 22px", borderRadius: 14, cursor: "pointer",
                  background: `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`,
                  border: "none", color: "white", fontFamily: T.display,
                  fontWeight: 900, fontSize: 12, letterSpacing: 1.5,
                  opacity: bidLoading || !amount ? 0.45 : 1,
                  transition: "all 0.2s",
                  boxShadow: "0 4px 16px rgba(6,200,224,0.25)",
                }}
                onMouseOver={e => { if (!bidLoading && amount) e.currentTarget.style.filter = "brightness(1.12)"; }}
                onMouseOut={e => { e.currentTarget.style.filter = "none"; }}
              >
                {bidLoading ? "..." : "TEKLİF VER"}
              </button>
            </form>
          </>
        )}

        {/* Status feedback */}
        {status && (
          <div style={{
            padding: "9px 14px", borderRadius: 10, textAlign: "center",
            fontFamily: T.display, fontWeight: 700, fontSize: "0.78rem",
            background: status.type === "success" ? "rgba(16,216,138,0.1)" : "rgba(240,62,62,0.1)",
            color: status.type === "success" ? T.green : T.red,
            border: `1px solid ${status.type === "success" ? "rgba(16,216,138,0.22)" : "rgba(240,62,62,0.22)"}`,
          }}>
            {status.msg}
          </div>
        )}

        {/* Buy now */}
        {!isOwner && buyItNowPrice && (
          <button
            onClick={onBuyNow} disabled={loading}
            style={{
              width: "100%", padding: "13px 0", borderRadius: 14, cursor: "pointer",
              background: "rgba(6,200,224,0.07)",
              border: "1px solid rgba(6,200,224,0.28)",
              color: T.teal, fontFamily: T.display, fontWeight: 800, fontSize: 13,
              letterSpacing: 0.5, transition: "all 0.2s",
            }}
            onMouseOver={e => {
              e.currentTarget.style.background = "rgba(6,200,224,0.14)";
              e.currentTarget.style.boxShadow = "0 0 20px rgba(6,200,224,0.15)";
            }}
            onMouseOut={e => {
              e.currentTarget.style.background = "rgba(6,200,224,0.07)";
              e.currentTarget.style.boxShadow = "none";
            }}
          >
            ⚡ Hemen Al — {fmt(buyItNowPrice)}
          </button>
        )}
      </div>
    </>
  );
}
