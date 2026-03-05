"use client";

// ─── FinalizationOverlay ──────────────────────────────────────────────────────

const formatPrice = (val: number) =>
    new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(val);

interface FinalizationOverlayProps {
    winnerName: string;
    amount?: number | null;
    onClose: () => void;
}

export function FinalizationOverlay({ winnerName, amount, onClose }: FinalizationOverlayProps) {
    return (
        <div style={{
            position: "absolute",
            inset: 0,
            background: "rgba(0,0,0,0.85)",
            backdropFilter: "blur(20px)",
            WebkitBackdropFilter: "blur(20px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 9000,
        }}>
            <div style={{
                background: "rgba(255,255,255,0.05)",
                border: "1px solid rgba(255,215,0,0.4)",
                borderRadius: "24px",
                padding: "40px",
                textAlign: "center",
                maxWidth: "360px",
                boxShadow: "0 25px 60px rgba(0,0,0,0.6), 0 0 40px rgba(255,215,0,0.15)",
            }}>
                <div style={{ fontSize: "4rem", marginBottom: "12px" }}>🎉</div>
                <h2 style={{ color: "#FFD700", fontWeight: 900, fontSize: "1.6rem", marginBottom: "8px" }}>
                    SATIŞ TAMAMLANDI!
                </h2>
                <p style={{ color: "rgba(255,255,255,0.8)", fontSize: "1rem", marginBottom: "4px" }}>
                    Kazanan: <strong style={{ color: "white" }}>{winnerName}</strong>
                </p>
                {amount != null && (
                    <p style={{ color: "#22c55e", fontWeight: 900, fontSize: "1.5rem", marginBottom: "24px" }}>
                        {formatPrice(amount)}
                    </p>
                )}
                <button
                    onClick={onClose}
                    style={{
                        background: "linear-gradient(135deg, #FFD700, #FFA500)",
                        color: "#000",
                        border: "none",
                        borderRadius: "100px",
                        padding: "12px 32px",
                        fontWeight: 900,
                        fontSize: "1rem",
                        cursor: "pointer",
                    }}
                >
                    Tamam
                </button>
            </div>
        </div>
    );
}

// ─── SoldOverlay (permanent SATILDI state) ────────────────────────────────────

interface SoldOverlayProps {
    winnerName: string;
    price: number;
    isOwner: boolean;
    onClose: () => void;
    onReset?: () => void;
}

export function SoldOverlay({ winnerName, price, isOwner, onClose, onReset }: SoldOverlayProps) {
    return (
        <div style={{
            position: "absolute",
            inset: 0,
            background: "rgba(0,0,0,0.9)",
            backdropFilter: "blur(24px)",
            WebkitBackdropFilter: "blur(24px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 8500,
        }}>
            <div style={{
                background: "linear-gradient(135deg, rgba(34,197,94,0.15), rgba(0,0,0,0.6))",
                border: "2px solid rgba(34,197,94,0.4)",
                borderRadius: "28px",
                padding: "48px 40px",
                textAlign: "center",
                maxWidth: "380px",
            }}>
                <div style={{ fontSize: "5rem", marginBottom: "16px" }}>🏆</div>
                <div style={{
                    background: "rgba(34,197,94,0.2)",
                    border: "1px solid rgba(34,197,94,0.4)",
                    borderRadius: "100px",
                    padding: "8px 24px",
                    color: "#22c55e",
                    fontWeight: 900,
                    fontSize: "1.2rem",
                    letterSpacing: "2px",
                    marginBottom: "16px",
                    display: "inline-block",
                }}>
                    SATILDI
                </div>
                <p style={{ color: "rgba(255,255,255,0.7)", margin: "0 0 8px" }}>
                    Kazanan: <strong style={{ color: "white" }}>{winnerName}</strong>
                </p>
                <p style={{ color: "#FFD700", fontWeight: 900, fontSize: "1.8rem", margin: "0 0 28px" }}>
                    {formatPrice(price)}
                </p>

                <div style={{ display: "flex", gap: "12px", justifyContent: "center" }}>
                    <button
                        onClick={onClose}
                        style={{
                            background: "rgba(255,255,255,0.1)",
                            color: "white",
                            border: "1px solid rgba(255,255,255,0.2)",
                            borderRadius: "100px",
                            padding: "12px 24px",
                            fontWeight: 700,
                            cursor: "pointer",
                        }}
                    >
                        Kapat
                    </button>
                    {isOwner && onReset && (
                        <button
                            onClick={onReset}
                            style={{
                                background: "linear-gradient(135deg, #00B4CC, #008da1)",
                                color: "white",
                                border: "none",
                                borderRadius: "100px",
                                padding: "12px 24px",
                                fontWeight: 800,
                                cursor: "pointer",
                            }}
                        >
                            Yeni Ürün
                        </button>
                    )}
                </div>
            </div>
        </div>
    );
}

// ─── BroadcastEndedScreen ─────────────────────────────────────────────────────

export function BroadcastEndedScreen() {
    return (
        <div style={{
            position: "absolute",
            inset: 0,
            background: "linear-gradient(135deg, #0f172a, #1e293b)",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            color: "white",
            zIndex: 100,
        }}>
            <div style={{ fontSize: "4rem", marginBottom: "16px" }}>📡</div>
            <h2 style={{ fontWeight: 900, fontSize: "1.8rem", marginBottom: "8px" }}>Yayın Sona Erdi</h2>
            <p style={{ color: "rgba(255,255,255,0.6)" }}>Yayıncı canlı yayını kapattı.</p>
            <button
                onClick={() => (window.location.href = "/")}
                style={{
                    marginTop: "28px",
                    background: "rgba(255,255,255,0.1)",
                    border: "1px solid rgba(255,255,255,0.2)",
                    borderRadius: "100px",
                    padding: "12px 28px",
                    color: "white",
                    fontWeight: 700,
                    cursor: "pointer",
                }}
            >
                Ana Sayfaya Dön
            </button>
        </div>
    );
}
