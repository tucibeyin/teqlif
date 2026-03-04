"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import DeleteAdButton from "./DeleteAdButton";
import RepublishAdButton from "./RepublishAdButton";

function formatPrice(price: number) {
    return new Intl.NumberFormat("tr-TR", {
        style: "currency",
        currency: "TRY",
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
    }).format(price);
}

function timeAgo(date: Date) {
    const diff = Date.now() - new Date(date).getTime();
    if (diff < 60000) return "Az önce";
    if (diff < 3600000) return `${Math.floor(diff / 60000)} dakika önce`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)} saat önce`;
    if (diff < 2592000000) return `${Math.floor(diff / 86400000)} gün önce`;
    if (diff < 31536000000) return `${Math.floor(diff / 2592000000)} ay önce`;
    return `${Math.floor(diff / 31536000000)} yıl önce`;
}

export default function UserAdsTabs({ ads }: { ads: any[] }) {
    const [tab, setTab] = useState<"ACTIVE" | "PASSIVE">("ACTIVE");

    const activeAds = ads.filter((ad: any) => ad.status === "ACTIVE" && !(ad.expiresAt && new Date(ad.expiresAt) < new Date()));
    const passiveAds = ads.filter((ad: any) => ad.status !== "ACTIVE" || (ad.expiresAt && new Date(ad.expiresAt) < new Date()));

    const currentAds = tab === "ACTIVE" ? activeAds : passiveAds;

    return (
        <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
            {/* Tabs */}
            <div style={{ display: "flex", gap: "0.5rem", borderBottom: "1px solid var(--border)", paddingBottom: "0.5rem" }}>
                <button
                    onClick={() => setTab("ACTIVE")}
                    style={{
                        padding: "0.5rem 1rem",
                        background: tab === "ACTIVE" ? "var(--primary)" : "transparent",
                        color: tab === "ACTIVE" ? "white" : "var(--text-secondary)",
                        border: "none",
                        borderRadius: "var(--radius-full)",
                        fontWeight: 700,
                        cursor: "pointer",
                        transition: "all 0.2s"
                    }}
                >
                    Aktif İlanlarım ({activeAds.length})
                </button>
                <button
                    onClick={() => setTab("PASSIVE")}
                    style={{
                        padding: "0.5rem 1rem",
                        background: tab === "PASSIVE" ? "var(--gray-200)" : "transparent",
                        color: tab === "PASSIVE" ? "black" : "var(--text-secondary)",
                        border: "none",
                        borderRadius: "var(--radius-full)",
                        fontWeight: 700,
                        cursor: "pointer",
                        transition: "all 0.2s"
                    }}
                >
                    Pasif İlanlarım ({passiveAds.length})
                </button>
            </div>

            {/* Ads List */}
            {currentAds.length === 0 ? (
                <div className="empty-state">
                    <div className="empty-state-icon">📭</div>
                    <div className="empty-state-title">Bu sekmede ilan bulunmuyor</div>
                    {tab === "ACTIVE" && (
                        <Link href="/post-ad" className="btn btn-primary" style={{ marginTop: "1rem" }}>
                            İlan Ver
                        </Link>
                    )}
                </div>
            ) : (
                <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                    {currentAds.map((ad: any) => {
                        const isExpired = ad.expiresAt ? new Date(ad.expiresAt) < new Date() : false;
                        const isPassive = tab === "PASSIVE";

                        return (
                            <div key={ad.id} className="card" style={{ opacity: isPassive ? 0.6 : 1, position: "relative", overflow: "hidden" }}>
                                {isPassive && (
                                    <div style={{
                                        position: "absolute",
                                        top: 12, left: -24,
                                        background: "red", color: "white",
                                        fontWeight: 900, fontSize: "0.7rem",
                                        padding: "2px 24px",
                                        transform: "rotate(-45deg)",
                                        textTransform: "uppercase",
                                        zIndex: 10,
                                        boxShadow: "0 2px 5px rgba(0,0,0,0.3)"
                                    }}>
                                        {ad.status === "SOLD" ? "Satıldı" : "Pasif"}
                                    </div>
                                )}
                                <div className="card-body" style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                    {ad.images && ad.images.length > 0 ? (
                                        <Image src={ad.images[0]} alt={ad.title} width={48} height={48} style={{ objectFit: "cover", borderRadius: "10px", filter: isPassive ? "grayscale(100%)" : "none" }} />
                                    ) : (
                                        <span style={{ fontSize: "2rem", filter: isPassive ? "grayscale(100%)" : "none" }}>{ad.category.icon}</span>
                                    )}
                                    <div style={{ flex: 1 }}>
                                        <Link href={`/ad/${ad.id}`} style={{ color: "var(--text-primary)", fontWeight: 600, fontSize: "0.9375rem" }}>
                                            {ad.title}
                                        </Link>
                                        <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                            {ad.province.name} · {timeAgo(ad.createdAt)} · {ad._count?.bids || 0} teqlif
                                        </div>
                                    </div>
                                    <div style={{ textAlign: "right", display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "0.5rem" }}>
                                        <div style={{ color: "var(--primary)", fontWeight: 700 }}>
                                            {(() => {
                                                if (ad.isFixedPrice) return formatPrice(ad.price);
                                                const highestBid = ad.bids?.[0]?.amount;
                                                if (highestBid) return formatPrice(highestBid);
                                                return ad.startingBid ? formatPrice(ad.startingBid) : "Serbest teqlif";
                                            })()}
                                        </div>
                                        <span className={`badge badge-${isExpired ? 'expired' : ad.status?.toLowerCase()}`}>
                                            {isExpired ? "Süresi Dolmuş" : ad.status === "ACTIVE" ? "Aktif" : ad.status === "SOLD" ? "Satıldı" : "Pasif"}
                                        </span>
                                        <div style={{ display: "flex", gap: "0.5rem", marginTop: "0.5rem" }}>
                                            {isExpired && <RepublishAdButton id={ad.id} />}
                                            {ad.status !== 'SOLD' && (
                                                <Link
                                                    href={`/edit-ad/${ad.id}`}
                                                    style={{
                                                        padding: "0.25rem 0.5rem",
                                                        borderRadius: "var(--radius-sm)",
                                                        fontSize: "0.875rem",
                                                        fontWeight: 600,
                                                        color: "var(--text-secondary)",
                                                        background: "var(--bg-secondary)",
                                                        textDecoration: "none"
                                                    }}
                                                >
                                                    Düzenle
                                                </Link>
                                            )}
                                            <DeleteAdButton id={ad.id} />
                                        </div>
                                    </div>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}
        </div>
    );
}
