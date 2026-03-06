"use client";

const T = {
  glass: "rgba(255,255,255,0.04)",
  glassBorder: "rgba(255,255,255,0.07)",
  teal: "#06C8E0",
  red: "#F03E3E",
  text: "#EDF2F7",
  muted: "#3D526A",
  display: "'Syne', system-ui, sans-serif",
};

function PulsingDot({ color }: { color: string }) {
  return (
    <>
      <style>{`
        @keyframes tq-ping {
          75%, 100% { transform: scale(2.2); opacity: 0; }
        }
      `}</style>
      <span style={{ position: "relative", display: "inline-flex", width: 8, height: 8 }}>
        <span style={{
          position: "absolute", inset: 0, borderRadius: "50%",
          background: color, opacity: 0.5,
          animation: "tq-ping 1.6s cubic-bezier(0,0,0.2,1) infinite",
        }} />
        <span style={{ width: 8, height: 8, borderRadius: "50%", background: color, display: "block" }} />
      </span>
    </>
  );
}

interface TopHUDProps {
  adOwnerName: string;
  participantCount: number;
  isOwner: boolean;
  onClose: () => void;
}

export function TopHUD({ adOwnerName, participantCount, isOwner, onClose }: TopHUDProps) {
  return (
    <div
      id="arena-top-hud"
      style={{
        position: "absolute", top: 0, left: 0, right: 0,
        padding: "18px 20px", zIndex: 200,
        display: "flex", justifyContent: "space-between", alignItems: "center",
        background: "linear-gradient(to bottom, rgba(6,8,16,0.92) 0%, rgba(6,8,16,0.4) 70%, transparent 100%)",
        pointerEvents: "none",
      }}>

      {/* Left: seller pill + LIVE badge */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, pointerEvents: "auto" }}>
        <div style={{
          display: "flex", alignItems: "center", gap: 9,
          background: T.glass, backdropFilter: "blur(20px)",
          WebkitBackdropFilter: "blur(20px)",
          border: `1px solid ${T.glassBorder}`,
          borderRadius: 100, padding: "5px 12px 5px 5px",
        }}>
          <div style={{
            width: 30, height: 30, borderRadius: "50%", flexShrink: 0,
            background: `linear-gradient(135deg, ${T.teal}, #0487A0)`,
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 12, fontWeight: 900, color: "white", fontFamily: T.display,
          }}>
            {adOwnerName.charAt(0).toUpperCase()}
          </div>
          <span style={{
            fontSize: 13, fontWeight: 700, color: T.text,
            fontFamily: T.display, letterSpacing: 0.2,
          }}>
            {adOwnerName}
          </span>
        </div>

        {/* LIVE badge — glowing */}
        <div style={{
          display: "flex", alignItems: "center", gap: 5,
          background: "rgba(240,62,62,0.12)",
          border: "1px solid rgba(240,62,62,0.3)",
          borderRadius: 100, padding: "5px 11px",
          boxShadow: "0 0 14px rgba(240,62,62,0.2)",
        }}>
          <PulsingDot color={T.red} />
          <span style={{
            fontSize: 10, fontWeight: 900, color: T.red,
            fontFamily: T.display, letterSpacing: 1.5,
          }}>
            CANLI
          </span>
        </div>
      </div>

      {/* Right: viewer count + close */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, pointerEvents: "auto" }}>
        <div style={{
          display: "flex", alignItems: "center", gap: 6,
          background: T.glass, backdropFilter: "blur(20px)",
          WebkitBackdropFilter: "blur(20px)",
          border: `1px solid ${T.glassBorder}`,
          borderRadius: 100, padding: "6px 14px",
        }}>
          <span style={{ fontSize: 12 }}>👁</span>
          <span style={{ fontSize: 13, fontWeight: 700, color: T.text, fontFamily: T.display }}>
            {participantCount}
          </span>
        </div>

        <button
          onClick={onClose}
          title={isOwner ? "Yayını Bitir" : "Çık"}
          style={{
            width: 34, height: 34, borderRadius: "50%",
            background: isOwner ? "rgba(240,62,62,0.15)" : T.glass,
            border: isOwner ? "1px solid rgba(240,62,62,0.32)" : `1px solid ${T.glassBorder}`,
            color: isOwner ? T.red : T.muted,
            fontSize: 13, cursor: "pointer",
            display: "flex", alignItems: "center", justifyContent: "center",
            transition: "all 0.2s",
            backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)",
          }}
          onMouseOver={e => {
            e.currentTarget.style.background = isOwner
              ? "rgba(240,62,62,0.28)"
              : "rgba(255,255,255,0.09)";
          }}
          onMouseOut={e => {
            e.currentTarget.style.background = isOwner
              ? "rgba(240,62,62,0.15)"
              : T.glass;
          }}
        >
          ✕
        </button>
      </div>
    </div>
  );
}
