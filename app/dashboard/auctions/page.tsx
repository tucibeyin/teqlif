"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import Link from "next/link";

interface AuctionEntry {
    id: string;
    title: string;
    images: string[];
    updatedAt: string;
    bids: { amount: number; user?: { id: string; name: string } }[];
    user?: { id: string; name: string }; // seller (for won)
}

function formatPrice(n: number) {
    return new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY", minimumFractionDigits: 0 }).format(n);
}

function imageUrl(path: string) {
    if (!path) return "/placeholder.png";
    if (path.startsWith("http")) return path;
    return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/ad-images/${path}`;
}

function AuctionCard({
    ad,
    counterparty,
    counterpartyId,
    label,
    finalPrice,
}: {
    ad: AuctionEntry;
    counterparty: string;
    counterpartyId: string;
    label: string;
    finalPrice: number;
}) {
    const router = useRouter();
    const [loading, setLoading] = useState(false);

    const handleMessage = async () => {
        setLoading(true);
        try {
            const res = await fetch("/api/conversations", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ userId: counterpartyId, adId: ad.id }),
            });
            if (res.ok) {
                router.push("/dashboard/messages");
            }
        } catch {
            /* ignore */
        } finally {
            setLoading(false);
        }
    };

    const thumb = ad.images?.[0] ? imageUrl(ad.images[0]) : null;

    return (
        <div className="auction-card">
            <div className="auction-card-inner">
                <div className="auction-thumb">
                    {thumb ? (
                        <Image src={thumb} alt={ad.title} width={80} height={80} style={{ objectFit: "cover", borderRadius: 12 }} />
                    ) : (
                        <div className="auction-thumb-placeholder">🏷️</div>
                    )}
                </div>
                <div className="auction-info">
                    <Link href={`/ad/${ad.id}`} className="auction-title">{ad.title}</Link>
                    <div className="auction-price">{formatPrice(finalPrice)}</div>
                    <div className="auction-counterparty">
                        <span className="auction-label">{label}:</span> {counterparty}
                    </div>
                </div>
                <div className="auction-actions">
                    <button
                        className="btn-message"
                        onClick={handleMessage}
                        disabled={loading}
                    >
                        {loading ? "..." : "💬 Mesaj Gönder"}
                    </button>
                </div>
            </div>
            <style jsx>{`
                .auction-card {
                    background: white;
                    border: 1px solid #e8edf2;
                    border-radius: 16px;
                    padding: 16px;
                    margin-bottom: 12px;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.04);
                    transition: box-shadow 0.2s;
                }
                .auction-card:hover { box-shadow: 0 4px 16px rgba(0,0,0,0.08); }
                .auction-card-inner { display: flex; align-items: center; gap: 16px; }
                .auction-thumb { flex-shrink: 0; }
                .auction-thumb-placeholder {
                    width: 80px; height: 80px; background: #f4f7fa;
                    border-radius: 12px; display: flex; align-items: center;
                    justify-content: center; font-size: 28px;
                }
                .auction-info { flex: 1; min-width: 0; }
                .auction-title {
                    font-weight: 700; font-size: 1rem; color: #1a1a2e;
                    text-decoration: none; display: block; white-space: nowrap;
                    overflow: hidden; text-overflow: ellipsis;
                }
                .auction-title:hover { color: var(--primary); }
                .auction-price { font-size: 1.25rem; font-weight: 800; color: #10b981; margin: 4px 0; }
                .auction-counterparty { font-size: 0.85rem; color: #6b7280; }
                .auction-label { font-weight: 600; color: #374151; }
                .auction-actions { flex-shrink: 0; }
                .btn-message {
                    background: linear-gradient(135deg, #00B4CC, #008DA0);
                    color: white; border: none; border-radius: 24px;
                    padding: 10px 20px; font-weight: 700; font-size: 0.85rem;
                    cursor: pointer; white-space: nowrap; transition: opacity 0.2s;
                }
                .btn-message:hover { opacity: 0.85; }
                .btn-message:disabled { opacity: 0.5; cursor: not-allowed; }
            `}</style>
        </div>
    );
}

export default function AuctionHistoryPage() {
    const [tab, setTab] = useState<"won" | "sold">("won");
    const [data, setData] = useState<{ won: AuctionEntry[]; sold: AuctionEntry[] } | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        fetch("/api/profile/auctions")
            .then((r) => r.json())
            .then(setData)
            .finally(() => setLoading(false));
    }, []);

    const wonList = data?.won ?? [];
    const soldList = data?.sold ?? [];

    return (
        <div className="dashboard">
            <div className="container" style={{ maxWidth: 760 }}>
                <div className="dashboard-header">
                    <div>
                        <h1 className="dashboard-name">🏆 Müzayede Geçmişim</h1>
                        <p className="text-muted text-sm">Kazandığınız ve sattığınız müzaydeler</p>
                    </div>
                    <Link href="/dashboard" className="btn" style={{ background: "#f4f7fa", color: "#374151", fontWeight: 600 }}>
                        ← Panele Dön
                    </Link>
                </div>

                {/* Tabs */}
                <div style={{ display: "flex", gap: 8, margin: "24px 0 20px" }}>
                    {(["won", "sold"] as const).map((t) => (
                        <button
                            key={t}
                            onClick={() => setTab(t)}
                            style={{
                                padding: "10px 28px", borderRadius: 24,
                                fontWeight: 700, fontSize: "0.95rem", border: "2px solid",
                                cursor: "pointer", transition: "all 0.2s",
                                background: tab === t ? "var(--primary)" : "white",
                                borderColor: tab === t ? "var(--primary)" : "#e8edf2",
                                color: tab === t ? "white" : "#374151",
                            }}
                        >
                            {t === "won" ? `🏅 Kazandıklarım (${wonList.length})` : `💰 Sattıklarım (${soldList.length})`}
                        </button>
                    ))}
                </div>

                {loading ? (
                    <div style={{ textAlign: "center", padding: "48px 0", color: "#9aaab8" }}>Yükleniyor...</div>
                ) : tab === "won" ? (
                    wonList.length === 0 ? (
                        <div className="empty-state">
                            <span style={{ fontSize: 48 }}>🏅</span>
                            <p>Henüz kazandığınız bir müzayede yok.</p>
                        </div>
                    ) : (
                        wonList.map((ad) => (
                            <AuctionCard
                                key={ad.id}
                                ad={ad}
                                counterparty={ad.user?.name ?? "Satıcı"}
                                counterpartyId={ad.user?.id ?? ""}
                                label="Satıcı"
                                finalPrice={ad.bids?.[0]?.amount ?? 0}
                            />
                        ))
                    )
                ) : (
                    soldList.length === 0 ? (
                        <div className="empty-state">
                            <span style={{ fontSize: 48 }}>💰</span>
                            <p>Henüz sattığınız bir müzayede yok.</p>
                        </div>
                    ) : (
                        soldList.map((ad) => (
                            <AuctionCard
                                key={ad.id}
                                ad={ad}
                                counterparty={ad.bids?.[0]?.user?.name ?? "Alıcı"}
                                counterpartyId={ad.bids?.[0]?.user?.id ?? ""}
                                label="Alıcı"
                                finalPrice={ad.bids?.[0]?.amount ?? 0}
                            />
                        ))
                    )
                )}
            </div>
        </div>
    );
}
