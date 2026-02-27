"use client";
import { useState } from "react";
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
            setError(`Teklifiniz minimum ${formatted.format(currentHighest + minStep)} olmalıdır.`);
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
            setError(data.error || "Teklif verilemedi.");
        } else {
            setSuccess("🎉 Teklifiniz başarıyla verildi!");
            router.refresh();
        }
    }

    return (
        <form onSubmit={handleBid}>
            {error && (
                <div className="error-msg" style={{ marginBottom: "0.75rem" }}>
                    {error}
                </div>
            )}
            {success && (
                <div
                    style={{
                        background: "rgba(63, 185, 80, 0.1)",
                        border: "1px solid rgba(63, 185, 80, 0.3)",
                        color: "var(--accent-green)",
                        padding: "0.625rem 1rem",
                        borderRadius: "var(--radius-md)",
                        fontSize: "0.875rem",
                        marginBottom: "0.75rem",
                    }}
                >
                    {success}
                </div>
            )}
            <div className="form-group" style={{ marginBottom: "0.75rem" }}>
                <label>Teklifiniz (₺)</label>
                <div style={{ position: "relative", display: "flex", alignItems: "center" }}>
                    <input
                        id="bid-amount-text"
                        type="text"
                        className="input"
                        value={displayAmount}
                        onChange={(e) => {
                            const val = e.target.value.replace(/[^0-9]/g, "");
                            if (!val) {
                                setDisplayAmount("");
                            } else {
                                setDisplayAmount(new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)));
                            }
                        }}
                        required
                        style={{ paddingRight: "1rem" }}
                    />
                </div>
                <span className="text-muted" style={{ fontSize: "0.75rem", marginTop: "0.25rem", display: "block" }}>
                    Minimum: {formatted.format(currentHighest + minStep)}
                </span>
            </div>
            <button
                type="submit"
                id="submit-bid"
                className="btn btn-primary btn-full btn-lg"
                disabled={loading}
            >
                {loading ? "Teklif veriliyor..." : "🔨 Teklif Ver"}
            </button>
        </form>
    );
}
