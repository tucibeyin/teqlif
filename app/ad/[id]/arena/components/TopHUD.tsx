"use client";

const HUD_CONTAINER: React.CSSProperties = {
    position: "absolute",
    top: "20px",
    left: "16px",
    right: "16px",
    zIndex: 200,
    display: "flex",
    justifyContent: "space-between",
    alignItems: "flex-start",
    pointerEvents: "none",
};

const AVATAR_PILL: React.CSSProperties = {
    display: "flex",
    alignItems: "center",
    background: "rgba(0,0,0,0.5)",
    backdropFilter: "blur(10px)",
    borderRadius: "100px",
    padding: "4px 16px 4px 4px",
    border: "1px solid rgba(255,255,255,0.1)",
};

const AVATAR_CIRCLE: React.CSSProperties = {
    width: "36px",
    height: "36px",
    borderRadius: "50%",
    background: "#ef4444",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "16px",
    fontWeight: "bold",
    color: "white",
    marginRight: "8px",
};

const CLOSE_BTN: React.CSSProperties = {
    background: "rgba(0,0,0,0.4)",
    border: "1px solid rgba(255,255,255,0.2)",
    borderRadius: "50%",
    width: "40px",
    height: "40px",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    color: "white",
    cursor: "pointer",
    backdropFilter: "blur(10px)",
};

const VIEWER_BADGE: React.CSSProperties = {
    display: "flex",
    alignItems: "center",
    background: "rgba(0,0,0,0.5)",
    backdropFilter: "blur(10px)",
    borderRadius: "100px",
    padding: "6px 12px",
    border: "1px solid rgba(255,255,255,0.1)",
    color: "white",
    fontSize: "0.8rem",
    gap: "6px",
    marginTop: "8px",
};

interface TopHUDProps {
    adOwnerName: string;
    participantCount: number;
    isOwner: boolean;
    onClose: () => void;
}

export function TopHUD({ adOwnerName, participantCount, isOwner, onClose }: TopHUDProps) {
    return (
        <div style={HUD_CONTAINER}>
            {/* Left: Avatar + viewer count */}
            <div style={{ display: "flex", flexDirection: "column", gap: "8px", pointerEvents: "auto" }}>
                <div style={AVATAR_PILL}>
                    <div style={AVATAR_CIRCLE}>
                        {adOwnerName.charAt(0).toUpperCase()}
                    </div>
                    <span style={{ color: "white", fontSize: "0.85rem", fontWeight: 700 }}>
                        {adOwnerName}
                    </span>
                </div>

                <div style={VIEWER_BADGE}>
                    <span style={{ color: "#ef4444", fontSize: "10px" }}>●</span>
                    <span>CANLI</span>
                    <span style={{ color: "rgba(255,255,255,0.6)" }}>|</span>
                    <span>👁 {participantCount}</span>
                </div>
            </div>

            {/* Right: Close button */}
            <div style={{ pointerEvents: "auto" }}>
                <button style={CLOSE_BTN} onClick={onClose} title={isOwner ? "Yayını Bitir" : "Çık"}>
                    ✕
                </button>
            </div>
        </div>
    );
}
