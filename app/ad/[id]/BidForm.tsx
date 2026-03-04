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
            background: "rgba(255, 255, 255, 0.7)",
            backdropFilter: "blur(20px)",
            WebkitBackdropFilter: "blur(20px)",
            border: "1px solid rgba(0, 180, 204, 0.2)",
            borderRadius: "1rem",
            padding: "1.25rem",
            color: "var(--text-primary)",
            boxShadow: "rgba(0, 180, 204, 0.1) 0px 20px 40px"
        }}>
            {error && (
                <div style={{ background: "rgba(239, 68, 68, 0.1)", color: "#dc2626", padding: "0.5rem", borderRadius: "0.5rem", fontSize: "0.875rem", marginBottom: "1rem", textAlign: "center" }}>
                    {error}
                </div>
            )}
            {success && (
                <div style={{ background: "rgba(34, 197, 94, 0.1)", color: "#16a34a", padding: "0.5rem", borderRadius: "0.5rem", fontSize: "0.875rem", marginBottom: "1rem", textAlign: "center" }}>
                    {success}
                </div>
            )}

            <div style={{ textAlign: "center", marginBottom: "1rem" }}>
                <div style={{ fontSize: "0.85rem", opacity: 0.6, textTransform: "uppercase", letterSpacing: "1px", marginBottom: "4px" }}>GÜNCEL FİYAT</div>
                <div className={`tabular-nums tracking-tight ${pulse ? "animate-pulse" : ""}`} style={{ fontSize: "2rem", fontWeight: 900, color: "var(--primary)", textShadow: "rgba(0, 180, 204, 0.2) 0px 2px 10px" }}>
                    {formatted.format(currentHighest)}
                </div>
            </div>

            <div style={{ display: "flex", gap: "8px", marginBottom: "1rem" }}>
                <button type="button" onClick={() => addFastBid(50)} disabled={loading} style={{ flex: 1, background: "rgba(0, 180, 204, 0.05)", border: "1px solid rgba(0, 180, 204, 0.15)", borderRadius: "20px", padding: "8px 0", color: "var(--primary)", fontWeight: 700, transition: "0.2s", cursor: loading ? "not-allowed" : "pointer" }} onMouseOver={e => e.currentTarget.style.background = "rgba(0, 180, 204, 0.1)"} onMouseOut={e => e.currentTarget.style.background = "rgba(0, 180, 204, 0.05)"}>+50 ₺</button>
                <button type="button" onClick={() => addFastBid(100)} disabled={loading} style={{ flex: 1, background: "rgba(0, 180, 204, 0.05)", border: "1px solid rgba(0, 180, 204, 0.15)", borderRadius: "20px", padding: "8px 0", color: "var(--primary)", fontWeight: 700, transition: "0.2s", cursor: loading ? "not-allowed" : "pointer" }} onMouseOver={e => e.currentTarget.style.background = "rgba(0, 180, 204, 0.1)"} onMouseOut={e => e.currentTarget.style.background = "rgba(0, 180, 204, 0.05)"}>+100 ₺</button>
                <button type="button" onClick={() => addFastBid(250)} disabled={loading} style={{ flex: 1, background: "rgba(0, 180, 204, 0.05)", border: "1px solid rgba(0, 180, 204, 0.15)", borderRadius: "20px", padding: "8px 0", color: "var(--primary)", fontWeight: 700, transition: "0.2s", cursor: loading ? "not-allowed" : "pointer" }} onMouseOver={e => e.currentTarget.style.background = "rgba(0, 180, 204, 0.1)"} onMouseOut={e => e.currentTarget.style.background = "rgba(0, 180, 204, 0.05)"}>+250 ₺</button>
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
                        background: "rgba(0, 180, 204, 0.03)",
                        border: "1px solid rgba(0, 180, 204, 0.2)",
                        borderRadius: "0.75rem",
                        padding: "1rem",
                        color: "var(--text-primary)",
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
                    background: loading ? "rgba(0, 180, 204, 0.2)" : "linear-gradient(135deg, rgb(0, 180, 204), rgb(0, 141, 161))",
                    color: "white",
                    border: "none",
                    borderRadius: "0.75rem",
                    padding: "1rem",
                    fontSize: "1.25rem",
                    fontWeight: 800,
                    cursor: loading ? "not-allowed" : "pointer",
                    boxShadow: loading ? "none" : "rgba(0, 180, 204, 0.4) 0px 4px 15px",
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
