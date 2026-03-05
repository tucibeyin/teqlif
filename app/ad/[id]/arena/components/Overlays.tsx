"use client";

const T = {
  teal: "#00B4CC",
  tealDark: "#008FA3",
  gold: "#F5C842",
  green: "#00E096",
  red: "#FF4757",
  text: "#E8EFF7",
  muted: "#4A6070",
  mono: "'DM Mono', 'Fira Code', 'Courier New', monospace",
  display: "'Syne', system-ui, sans-serif",
};

const fmt = (val: number) =>
  new Intl.NumberFormat("tr-TR").format(val) + " ₺";

const BACKDROP: React.CSSProperties = {
  position: "absolute", inset: 0,
  background: "rgba(7,11,15,0.92)",
  backdropFilter: "blur(24px)",
  WebkitBackdropFilter: "blur(24px)",
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
    <div style={{ ...BACKDROP, zIndex: 9000 }}>
      <style>{`
        @keyframes tq-popIn {
          from { opacity: 0; transform: scale(0.85); }
          to   { opacity: 1; transform: scale(1); }
        }
      `}</style>
      <div style={{
        background: "rgba(12,18,26,0.98)",
        border: "1px solid rgba(245,200,66,0.3)",
        borderRadius: 24, padding: "44px 40px",
        textAlign: "center", maxWidth: 360,
        boxShadow: "0 25px 60px rgba(0,0,0,0.8), 0 0 40px rgba(245,200,66,0.08)",
        animation: "tq-popIn 0.35s cubic-bezier(0.175,0.885,0.32,1.275)",
      }}>
        <div style={{ fontSize: "3.5rem", marginBottom: 12 }}>🎉</div>
        <div style={{
          fontFamily: T.display, fontWeight: 900, fontSize: "1.4rem",
          color: T.gold, marginBottom: 12, letterSpacing: 1,
        }}>
          SATIŞ TAMAMLANDI
        </div>
        <p style={{ color: T.muted, fontSize: "0.9rem", marginBottom: 4, fontFamily: T.display }}>
          Kazanan
        </p>
        <p style={{ color: T.text, fontWeight: 800, fontSize: "1.1rem", marginBottom: 16, fontFamily: T.display }}>
          {winnerName}
        </p>
        {amount != null && (
          <div style={{
            fontFamily: T.mono, fontSize: "1.8rem", fontWeight: 500,
            color: T.green, marginBottom: 28,
          }}>
            {fmt(amount)}
          </div>
        )}
        <button
          onClick={onClose}
          style={{
            background: `linear-gradient(135deg, ${T.gold}, #d4a017)`,
            color: "#0a0a0a", border: "none", borderRadius: 100,
            padding: "12px 36px", fontFamily: T.display,
            fontWeight: 900, fontSize: "0.95rem", cursor: "pointer",
            letterSpacing: 0.5,
          }}
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
    <div style={{ ...BACKDROP, zIndex: 8500 }}>
      <style>{`
        @keyframes tq-popIn {
          from { opacity: 0; transform: scale(0.85); }
          to   { opacity: 1; transform: scale(1); }
        }
      `}</style>
      <div style={{
        background: "rgba(12,18,26,0.98)",
        border: "1px solid rgba(0,224,150,0.2)",
        borderRadius: 28, padding: "48px 44px",
        textAlign: "center", maxWidth: 380,
        boxShadow: "0 30px 80px rgba(0,0,0,0.9), 0 0 60px rgba(0,224,150,0.06)",
        animation: "tq-popIn 0.4s cubic-bezier(0.175,0.885,0.32,1.275)",
      }}>
        <div style={{ fontSize: "4rem", marginBottom: 16 }}>🏆</div>

        {/* SATILDI badge */}
        <div style={{
          display: "inline-flex", alignItems: "center",
          background: "rgba(0,224,150,0.1)",
          border: "1px solid rgba(0,224,150,0.25)",
          borderRadius: 100, padding: "6px 24px",
          color: T.green, fontFamily: T.display,
          fontWeight: 900, fontSize: "0.9rem",
          letterSpacing: 3, marginBottom: 20,
        }}>
          SATILDI
        </div>

        <p style={{ color: T.muted, fontFamily: T.display, fontSize: "0.85rem", marginBottom: 4 }}>
          Kazanan
        </p>
        <p style={{ color: T.text, fontWeight: 800, fontSize: "1.15rem", marginBottom: 12, fontFamily: T.display }}>
          {winnerName}
        </p>
        <div style={{
          fontFamily: T.mono, fontSize: "2rem", fontWeight: 500,
          color: T.gold, marginBottom: 32,
        }}>
          {fmt(price)}
        </div>

        <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
          <button
            onClick={onClose}
            style={{
              background: "rgba(255,255,255,0.06)", color: T.text,
              border: "1px solid rgba(255,255,255,0.1)", borderRadius: 100,
              padding: "11px 24px", fontFamily: T.display,
              fontWeight: 700, fontSize: "0.9rem", cursor: "pointer",
              transition: "all 0.2s",
            }}
            onMouseOver={e => (e.currentTarget.style.background = "rgba(255,255,255,0.1)")}
            onMouseOut={e => (e.currentTarget.style.background = "rgba(255,255,255,0.06)")}
          >
            Kapat
          </button>
          {isOwner && onReset && (
            <button
              onClick={onReset}
              style={{
                background: `linear-gradient(135deg, ${T.teal}, ${T.tealDark})`,
                color: "white", border: "none", borderRadius: 100,
                padding: "11px 24px", fontFamily: T.display,
                fontWeight: 800, fontSize: "0.9rem", cursor: "pointer",
                transition: "all 0.2s",
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
    <div style={{
      position: "absolute", inset: 0,
      background: "linear-gradient(135deg, #070B0F, #0D1B2A)",
      display: "flex", flexDirection: "column",
      alignItems: "center", justifyContent: "center",
      color: T.text, zIndex: 100,
    }}>
      {/* Grid texture */}
      <div style={{
        position: "absolute", inset: 0, opacity: 0.03,
        backgroundImage: `repeating-linear-gradient(0deg, transparent, transparent 39px, rgba(0,180,204,0.5) 40px),
                          repeating-linear-gradient(90deg, transparent, transparent 39px, rgba(0,180,204,0.5) 40px)`,
        pointerEvents: "none",
      }} />

      <div style={{ fontSize: "3.5rem", marginBottom: 16 }}>📡</div>
      <h2 style={{
        fontFamily: T.display, fontWeight: 900, fontSize: "1.6rem",
        marginBottom: 8, letterSpacing: 0.5,
      }}>
        Yayın Sona Erdi
      </h2>
      <p style={{ color: T.muted, fontFamily: T.display, fontSize: "0.95rem" }}>
        Yayıncı canlı yayını kapattı.
      </p>
      <button
        onClick={() => (window.location.href = "/")}
        style={{
          marginTop: 28,
          background: "rgba(0,180,204,0.1)", border: "1px solid rgba(0,180,204,0.2)",
          borderRadius: 100, padding: "12px 32px",
          color: T.teal, fontFamily: T.display,
          fontWeight: 700, fontSize: "0.9rem", cursor: "pointer",
          transition: "all 0.2s",
        }}
        onMouseOver={e => (e.currentTarget.style.background = "rgba(0,180,204,0.18)")}
        onMouseOut={e => (e.currentTarget.style.background = "rgba(0,180,204,0.1)")}
      >
        Ana Sayfaya Dön
      </button>
    </div>
  );
}
