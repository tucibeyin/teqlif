"use client";

const T = {
  teal: "#00B4CC",
  red: "#FF4757",
  glass: "rgba(255,255,255,0.04)",
  glassBorder: "rgba(255,255,255,0.07)",
  text: "#E8EFF7",
  muted: "#4A6070",
  display: "'Syne', system-ui, sans-serif",
};

function PulsingDot({ color }: { color: string }) {
  return (
    <>
      <style>{`
        @keyframes tq-ping {
          75%, 100% { transform: scale(2); opacity: 0; }
        }
      `}</style>
      <span style={{ position: "relative", display: "inline-flex", width: 10, height: 10 }}>
        <span style={{
          position: "absolute", inset: 0, borderRadius: "50%",
          background: color, opacity: 0.4,
          animation: "tq-ping 1.5s cubic-bezier(0,0,0.2,1) infinite",
        }} />
        <span style={{ width: 10, height: 10, borderRadius: "50%", background: color, display: "block" }} />
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
    <div style={{
      position: "absolute", top: 0, left: 0, right: 0,
      padding: "16px 20px", zIndex: 200,
      display: "flex", justifyContent: "space-between", alignItems: "center",
      background: "linear-gradient(to bottom, rgba(7,11,15,0.85), transparent)",
      pointerEvents: "none",
    }}>
      {/* Left: seller pill */}
      <div style={{ display: "flex", alignItems: "center", gap: 10, pointerEvents: "auto" }}>
        <div style={{
          display: "flex", alignItems: "center", gap: 10,
          background: T.glass, backdropFilter: "blur(16px)",
          WebkitBackdropFilter: "blur(16px)",
          border: `1px solid ${T.glassBorder}`,
          borderRadius: 100, padding: "6px 14px 6px 6px",
        }}>
          {/* Avatar */}
          <div style={{
            width: 32, height: 32, borderRadius: "50%",
            background: `linear-gradient(135deg, ${T.teal}, #005F6B)`,
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 13, fontWeight: 800, color: "white", fontFamily: T.display,
          }}>
            {adOwnerName.charAt(0).toUpperCase()}
          </div>
          <span style={{ fontSize: 13, fontWeight: 700, color: T.text, fontFamily: T.display }}>
            {adOwnerName}
          </span>
          {/* LIVE badge */}
          <div style={{
            background: "rgba(255,71,87,0.15)", border: "1px solid rgba(255,71,87,0.3)",
            borderRadius: 100, padding: "2px 8px",
            display: "flex", alignItems: "center", gap: 5,
            fontSize: 10, fontWeight: 800, color: T.red, letterSpacing: 1,
          }}>
            <PulsingDot color={T.red} />
            CANLI
          </div>
        </div>
      </div>

      {/* Right: viewer count + close */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, pointerEvents: "auto" }}>
        <div style={{
          background: T.glass, backdropFilter: "blur(16px)",
          WebkitBackdropFilter: "blur(16px)",
          border: `1px solid ${T.glassBorder}`,
          borderRadius: 100, padding: "6px 14px",
          fontSize: 12, color: T.muted,
          display: "flex", alignItems: "center", gap: 6,
          fontFamily: T.display,
        }}>
          <span style={{ color: T.text }}>👁</span>
          <span style={{ color: T.text, fontWeight: 600 }}>{participantCount}</span>
        </div>

        <button
          onClick={onClose}
          title={isOwner ? "Yayını Bitir" : "Çık"}
          style={{
            width: 36, height: 36, borderRadius: "50%",
            background: "rgba(255,71,87,0.1)",
            border: "1px solid rgba(255,71,87,0.2)",
            color: T.red, fontSize: 14, cursor: "pointer",
            display: "flex", alignItems: "center", justifyContent: "center",
            transition: "all 0.2s",
          }}
          onMouseOver={e => (e.currentTarget.style.background = "rgba(255,71,87,0.25)")}
          onMouseOut={e => (e.currentTarget.style.background = "rgba(255,71,87,0.1)")}
        >
          ✕
        </button>
      </div>
    </div>
  );
}
