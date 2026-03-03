"use client";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";

interface BidFormProps {
    adId: string;
    currentHighest: number;
    minStep: number;
}

export default function BidForm({ adId, currentHighest, minStep }: BidFormProps) {
    const router = useRouter();
    const [displayAmount, setDisplayAmount] = useState(() => new Intl.NumberFormat("tr-TR").format(currentHighest + minStep));
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [success, setSuccess] = useState("");
    const [pulse, setPulse] = useState(false);

    useEffect(() => {
        setDisplayAmount(new Intl.NumberFormat("tr-TR").format(currentHighest + minStep));
        setPulse(true);
        const t = setTimeout(() => setPulse(false), 1000);
        return () => clearTimeout(t);
    }, [currentHighest, minStep]);

    const formatted = new Intl.NumberFormat("tr-TR", {
        style: "currency",
        currency: "TRY",
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
    });

    async function handleBid(e: React.FormEvent) {
        e.preventDefault();
        setLoading(true);
        setError("");
        setSuccess("");

        const rawAmount = parseInt(displayAmount.replace(/\./g, ""), 10);
        if (!rawAmount || rawAmount < currentHighest + minStep) {
            setError(`Teqlifiniz minimum ${formatted.format(currentHighest + minStep)} olmalıdır.`);
            setLoading(false);
            return;
        }

        const res = await fetch("/api/bids", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ adId, amount: rawAmount }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "Teqlif verilemedi.");
        } else {
            setSuccess("🎉 Teqlifiniz başarıyla verildi!");
            router.refresh();
        }
    }

    const getRaw = (val: string) => parseInt(val.replace(/\./g, ""), 10) || 0;

    function addFastBid(amount: number) {
        if (loading) return;
        const currentRaw = getRaw(displayAmount);
        const newDisplay = currentRaw + amount;
        setDisplayAmount(new Intl.NumberFormat("tr-TR").format(newDisplay));
    }

    return (
        <form onSubmit={handleBid} style={{
            background: "rgba(0, 0, 0, 0.4)",
            backdropFilter: "blur(20px)",
            WebkitBackdropFilter: "blur(20px)",
            border: "1px solid rgba(255, 255, 255, 0.15)",
            borderRadius: "1rem",
            padding: "1.25rem",
            color: "white",
            boxShadow: "0 20px 40px rgba(0,0,0,0.4)"
        }}>
            {error && (
                <div style={{ background: "rgba(239, 68, 68, 0.2)", color: "#fca5a5", padding: "0.5rem", borderRadius: "0.5rem", fontSize: "0.875rem", marginBottom: "1rem", textAlign: "center" }}>
                    {error}
                </div>
            )}
            {success && (
                <div style={{ background: "rgba(34, 197, 94, 0.2)", color: "#86efac", padding: "0.5rem", borderRadius: "0.5rem", fontSize: "0.875rem", marginBottom: "1rem", textAlign: "center" }}>
                    {success}
                </div>
            )}

            <div style={{ textAlign: "center", marginBottom: "1rem" }}>
                <div style={{ fontSize: "0.85rem", opacity: 0.8, textTransform: "uppercase", letterSpacing: "1px", marginBottom: "4px" }}>GÜNCEL FİYAT</div>
                <div className={`tabular-nums tracking-tight ${pulse ? "animate-pulse" : ""}`} style={{ fontSize: "2rem", fontWeight: 900, color: "#4ade80", textShadow: "0 2px 10px rgba(74, 222, 128, 0.4)" }}>
                    {formatted.format(currentHighest)}
                </div>
            </div>

            <div style={{ display: "flex", gap: "8px", marginBottom: "1rem" }}>
                <button type="button" onClick={() => addFastBid(50)} disabled={loading} style={{ flex: 1, background: "rgba(255,255,255,0.1)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "20px", padding: "8px 0", color: "white", fontWeight: 600, transition: "all 0.2s" }} onMouseOver={e => e.currentTarget.style.background = "rgba(255,255,255,0.2)"} onMouseOut={e => e.currentTarget.style.background = "rgba(255,255,255,0.1)"}>+50 ₺</button>
                <button type="button" onClick={() => addFastBid(100)} disabled={loading} style={{ flex: 1, background: "rgba(255,255,255,0.1)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "20px", padding: "8px 0", color: "white", fontWeight: 600, transition: "all 0.2s" }} onMouseOver={e => e.currentTarget.style.background = "rgba(255,255,255,0.2)"} onMouseOut={e => e.currentTarget.style.background = "rgba(255,255,255,0.1)"}>+100 ₺</button>
                <button type="button" onClick={() => addFastBid(250)} disabled={loading} style={{ flex: 1, background: "rgba(255,255,255,0.1)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "20px", padding: "8px 0", color: "white", fontWeight: 600, transition: "all 0.2s" }} onMouseOver={e => e.currentTarget.style.background = "rgba(255,255,255,0.2)"} onMouseOut={e => e.currentTarget.style.background = "rgba(255,255,255,0.1)"}>+250 ₺</button>
            </div>

            <div style={{ marginBottom: "1rem", position: "relative" }}>
                <input
                    type="text"
                    value={displayAmount}
                    onChange={(e) => {
                        const val = e.target.value.replace(/[^0-9]/g, "");
                        setDisplayAmount(val ? new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)) : "");
                    }}
                    disabled={loading}
                    required
                    style={{
                        width: "100%",
                        background: "rgba(0,0,0,0.3)",
                        border: "1px solid rgba(255,255,255,0.2)",
                        borderRadius: "0.75rem",
                        padding: "1rem",
                        color: "white",
                        fontSize: "1.25rem",
                        fontWeight: "bold",
                        textAlign: "center",
                        outline: "none"
                    }}
                />
            </div>

            <button
                type="submit"
                disabled={loading}
                style={{
                    width: "100%",
                    background: loading ? "gray" : "linear-gradient(135deg, #00B4CC, #008da1)",
                    color: "white",
                    border: "none",
                    borderRadius: "0.75rem",
                    padding: "1rem",
                    fontSize: "1.25rem",
                    fontWeight: 800,
                    cursor: loading ? "not-allowed" : "pointer",
                    boxShadow: loading ? "none" : "0 4px 15px rgba(0, 180, 204, 0.4)",
                    transition: "transform 0.1s, box-shadow 0.1s"
                }}
                onMouseDown={e => { if (!loading) e.currentTarget.style.transform = "scale(0.98)" }}
                onMouseUp={e => { if (!loading) e.currentTarget.style.transform = "scale(1)" }}
                onMouseLeave={e => { if (!loading) e.currentTarget.style.transform = "scale(1)" }}
            >
                {loading ? "GÖNDERİLİYOR..." : "🚀 teqlif ver"}
            </button>
        </form>
    );
}
