"use client";

const T = {
  teal: "#06C8E0",
  tealDark: "#059AAF",
  gold: "#F0B429",
  green: "#10D88A",
  red: "#F03E3E",
  text: "#EDF2F7",
  muted: "#3D526A",
  mono: "'DM Mono', monospace",
  display: "'Syne', system-ui, sans-serif",
};

const fmt = (val: number) =>
  new Intl.NumberFormat("tr-TR").format(val) + " ₺";

const BACKDROP: React.CSSProperties = {
  position: "absolute", inset: 0,
  background: "rgba(6,8,16,0.93)",
  backdropFilter: "blur(28px)",
  WebkitBackdropFilter: "blur(28px)",
  display: "flex", alignItems: "center", justifyContent: "center",
};

// ── FinalizationOverlay ────────────────────────────────────────────────────
interface FinalizationOverlayProps {
  winnerName: string;
  amount?: number | null;
  onClose: () => void;
}

export function FinalizationOverlay({ winnerName, amount, onClose }: FinalizationOverlayProps) {
  return (
    <div id="arena-finalization-overlay" style={{ ...BACKDROP, zIndex: 9000 }}>
      <style>{`
        @keyframes tq-popIn {
          from { opacity: 0; transform: scale(0.82) translateY(12px); }
          to   { opacity: 1; transform: scale(1) translateY(0); }
        }
      `}</style>
      <div style={{
        background: "rgba(10,14,24,0.99)",
        border: "1px solid rgba(240,180,41,0.25)",
        borderRadius: 28, padding: "48px 44px",
        textAlign: "center", maxWidth: 360, width: "90%",
        boxShadow: "0 30px 80px rgba(0,0,0,0.85), 0 0 50px rgba(240,180,41,0.07)",
        animation: "tq-popIn 0.38s cubic-bezier(0.175,0.885,0.32,1.275)",
      }}>
        <div style={{ fontSize: "3.8rem", marginBottom: 14 }}>🎉</div>
        <div style={{
          fontFamily: T.display, fontWeight: 900, fontSize: "1.35rem",
          color: T.gold, marginBottom: 14, letterSpacing: 1.5,
        }}>
          SATIŞ TAMAMLANDI
        </div>
        <p style={{
          color: T.muted, fontSize: "0.8rem", marginBottom: 4,
          fontFamily: T.display, letterSpacing: 0.5, textTransform: "uppercase",
        }}>
          Kazanan
        </p>
        <p style={{
          color: T.text, fontWeight: 800, fontSize: "1.15rem",
          marginBottom: 18, fontFamily: T.display,
        }}>
          {winnerName}
        </p>
        {amount != null && (
          <div style={{
            fontFamily: T.mono, fontSize: "2rem", fontWeight: 500,
            color: T.green, marginBottom: 32,
            textShadow: "0 0 20px rgba(16,216,138,0.35)",
          }}>
            {fmt(amount)}
          </div>
        )}
        <button
          onClick={onClose}
          style={{
            background: `linear-gradient(135deg, ${T.gold}, #c9920e)`,
            color: "#060810", border: "none", borderRadius: 100,
            padding: "13px 40px", fontFamily: T.display,
            fontWeight: 900, fontSize: "0.95rem", cursor: "pointer",
            letterSpacing: 0.8, boxShadow: "0 4px 20px rgba(240,180,41,0.35)",
            transition: "all 0.2s",
          }}
          onMouseOver={e => (e.currentTarget.style.filter = "brightness(1.1)")}
          onMouseOut={e => (e.currentTarget.style.filter = "none")}
        >
          Tamam
        </button>
      </div>
    </div>
  );
}

// ── SoldOverlay (permanent SATILDI state) ─────────────────────────────────
interface SoldOverlayProps {
  winnerName: string;
  price: number;
  isOwner: boolean;
  onClose: () => void;
  onReset?: () => void;
}

export function SoldOverlay({ winnerName, price, isOwner, onClose, onReset }: SoldOverlayProps) {
  return (
    <div id="arena-sold-overlay" style={{ ...BACKDROP, zIndex: 8500 }}>
      <style>{`
        @keyframes tq-popIn {
          from { opacity: 0; transform: scale(0.82) translateY(12px); }
          to   { opacity: 1; transform: scale(1) translateY(0); }
        }
        @keyframes tq-shimmer {
          0%   { background-position: -200% center; }
          100% { background-position: 200% center; }
        }
      `}</style>
      <div style={{
        background: "rgba(10,14,24,0.99)",
        border: "1px solid rgba(16,216,138,0.2)",
        borderRadius: 32, padding: "52px 48px",
        textAlign: "center", maxWidth: 400, width: "90%",
        boxShadow: "0 40px 100px rgba(0,0,0,0.9), 0 0 70px rgba(16,216,138,0.06)",
        animation: "tq-popIn 0.42s cubic-bezier(0.175,0.885,0.32,1.275)",
      }}>
        <div style={{ fontSize: "5rem", marginBottom: 18, lineHeight: 1 }}>🏆</div>

        {/* SATILDI badge — shimmer */}
        <div style={{
          display: "inline-flex", alignItems: "center",
          borderRadius: 100, padding: "7px 26px", marginBottom: 22,
          background: "linear-gradient(90deg, rgba(16,216,138,0.1), rgba(6,200,224,0.15), rgba(16,216,138,0.1))",
          backgroundSize: "200% auto",
          animation: "tq-shimmer 2.5s linear infinite",
          border: "1px solid rgba(16,216,138,0.25)",
          color: T.green, fontFamily: T.display,
          fontWeight: 900, fontSize: "0.88rem", letterSpacing: 4,
        }}>
          SATILDI
        </div>

        <p style={{
          color: T.muted, fontFamily: T.display, fontSize: "0.75rem",
          marginBottom: 5, letterSpacing: 1, textTransform: "uppercase",
        }}>
          Kazanan
        </p>
        <p style={{
          color: T.text, fontWeight: 800, fontSize: "1.2rem",
          marginBottom: 14, fontFamily: T.display,
        }}>
          {winnerName}
        </p>
        <div style={{
          fontFamily: T.mono, fontSize: "2.1rem", fontWeight: 500,
          color: T.gold, marginBottom: 36,
          textShadow: "0 0 24px rgba(240,180,41,0.3)",
        }}>
          {fmt(price)}
        </div>

        <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
          <button
            onClick={onClose}
            style={{
              background: "rgba(255,255,255,0.05)", color: T.text,
              border: "1px solid rgba(255,255,255,0.09)", borderRadius: 100,
              padding: "12px 26px", fontFamily: T.display,
              fontWeight: 700, fontSize: "0.9rem", cursor: "pointer",
              transition: "all 0.2s",
            }}
            onMouseOver={e => (e.currentTarget.style.background = "rgba(255,255,255,0.1)")}
            onMouseOut={e => (e.currentTarget.style.background = "rgba(255,255,255,0.05)")}
          >
            Kapat
          </button>
          {isOwner && onReset && (
            <button
              onClick={onReset}
              style={{
                background: `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`,
                color: "white", border: "none", borderRadius: 100,
                padding: "12px 26px", fontFamily: T.display,
                fontWeight: 900, fontSize: "0.9rem", cursor: "pointer",
                transition: "all 0.2s",
                boxShadow: "0 4px 18px rgba(6,200,224,0.3)",
              }}
              onMouseOver={e => (e.currentTarget.style.filter = "brightness(1.1)")}
              onMouseOut={e => (e.currentTarget.style.filter = "none")}
            >
              Yeni Ürün →
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── BroadcastEndedScreen ──────────────────────────────────────────────────
export function BroadcastEndedScreen() {
  return (
    <div
      id="arena-broadcast-ended-overlay"
      style={{
        position: "absolute", inset: 0,
        background: "radial-gradient(ellipse at center, #0D1626 0%, #060810 70%)",
        display: "flex", flexDirection: "column",
        alignItems: "center", justifyContent: "center",
        color: T.text, zIndex: 100, overflow: "hidden",
      }}>
      {/* Subtle dot grid */}
      <div style={{
        position: "absolute", inset: 0, opacity: 0.045,
        backgroundImage: `radial-gradient(circle, rgba(6,200,224,0.6) 1px, transparent 1px)`,
        backgroundSize: "28px 28px",
        pointerEvents: "none",
      }} />

      <div style={{ position: "relative", zIndex: 1, textAlign: "center" }}>
        <div style={{ fontSize: "3.8rem", marginBottom: 20 }}>📡</div>
        <h2 style={{
          fontFamily: T.display, fontWeight: 900, fontSize: "1.7rem",
          marginBottom: 10, letterSpacing: 0.5,
        }}>
          Yayın Sona Erdi
        </h2>
        <p style={{
          color: T.muted, fontFamily: T.display, fontSize: "0.92rem", marginBottom: 32,
        }}>
          Yayıncı canlı yayını kapattı.
        </p>
        <button
          onClick={() => (window.location.href = "/")}
          style={{
            background: "rgba(6,200,224,0.09)",
            border: "1px solid rgba(6,200,224,0.25)",
            borderRadius: 100, padding: "13px 36px",
            color: T.teal, fontFamily: T.display,
            fontWeight: 700, fontSize: "0.9rem", cursor: "pointer",
            transition: "all 0.2s",
            letterSpacing: 0.5,
          }}
          onMouseOver={e => {
            e.currentTarget.style.background = "rgba(6,200,224,0.16)";
            e.currentTarget.style.boxShadow = "0 0 20px rgba(6,200,224,0.2)";
          }}
          onMouseOut={e => {
            e.currentTarget.style.background = "rgba(6,200,224,0.09)";
            e.currentTarget.style.boxShadow = "none";
          }}
        >
          Ana Sayfaya Dön
        </button>
      </div>
    </div>
  );
}
