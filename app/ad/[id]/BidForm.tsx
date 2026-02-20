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
    const [amount, setAmount] = useState(String(currentHighest + minStep));
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [success, setSuccess] = useState("");

    async function handleBid(e: React.FormEvent) {
        e.preventDefault();
        setLoading(true);
        setError("");
        setSuccess("");

        const res = await fetch("/api/bids", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ adId, amount: Number(amount) }),
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

    const formatted = new Intl.NumberFormat("tr-TR", {
        style: "currency",
        currency: "TRY",
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });

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
                <input
                    id="bid-amount"
                    type="number"
                    className="input"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    min={currentHighest + minStep}
                    step={1}
                    required
                />
                <span className="text-muted" style={{ fontSize: "0.75rem" }}>
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
