"use client";

import { useState, useEffect, useRef } from "react";
import { useSession } from "next-auth/react";

export type PinPayload =
    | { adId: string; startingBid: number }
    | { customTitle: string; customPrice: number; startingBid: number };

interface PinItemModalProps {
    isOpen: boolean;
    onClose: () => void;
    onSubmit: (payload: PinPayload) => Promise<void>;
}

const T = {
    bg: "rgba(10,14,28,0.98)",
    border: "rgba(255,255,255,0.1)",
    inputBg: "rgba(255,255,255,0.05)",
    teal: "#06C8E0",
    text: "#EDF2F7",
    muted: "rgba(255,255,255,0.45)",
    display: "'Syne', system-ui, sans-serif",
};

const inputStyle: React.CSSProperties = {
    width: "100%",
    background: T.inputBg,
    border: `1px solid ${T.border}`,
    borderRadius: 10,
    padding: "10px 14px",
    color: T.text,
    fontSize: 13,
    fontFamily: T.display,
    outline: "none",
    boxSizing: "border-box",
};

interface AdListItem {
    id: string;
    title: string;
    price: number | null;
    startingBid: number | null;
    images: string[];
}

export function PinItemModal({ isOpen, onClose, onSubmit }: PinItemModalProps) {
    const { data: session } = useSession();
    const [tab, setTab] = useState<"quick" | "myads">("quick");
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    // Hızlı Ürün fields
    const [customTitle, setCustomTitle] = useState("");
    const [customPrice, setCustomPrice] = useState("");
    const [startingBid, setStartingBid] = useState("");
    const titleRef = useRef<HTMLInputElement>(null);

    // İlanlarım fields
    const [adsList, setAdsList] = useState<AdListItem[]>([]);
    const [adsLoading, setAdsLoading] = useState(false);
    const [selectedAdId, setSelectedAdId] = useState<string | null>(null);
    const [adStartingBid, setAdStartingBid] = useState("");

    // Focus & reset on open
    useEffect(() => {
        if (!isOpen) return;
        setError(null);
        setTab("quick");
        setCustomTitle("");
        setCustomPrice("");
        setStartingBid("");
        setSelectedAdId(null);
        setAdStartingBid("");
        setTimeout(() => titleRef.current?.focus(), 60);
    }, [isOpen]);

    // İlanlarım tab açılınca fetch
    useEffect(() => {
        if (tab !== "myads" || !session?.user?.id) return;
        setAdsLoading(true);
        fetch(`/api/ads?status=ACTIVE&userId=${session.user.id}`)
            .then(r => r.json())
            .then((data: any[]) => setAdsList(
                data.map(d => ({
                    id: d.id,
                    title: d.title,
                    price: d.price ?? null,
                    startingBid: d.startingBid ?? null,
                    images: d.images ?? [],
                }))
            ))
            .catch(() => setAdsList([]))
            .finally(() => setAdsLoading(false));
    }, [tab, session?.user?.id]);

    const handleSubmit = async () => {
        setError(null);
        let payload: PinPayload;

        if (tab === "quick") {
            if (!customTitle.trim()) { setError("Ürün adı zorunludur."); return; }
            const price = parseFloat(customPrice.replace(/\D/g, "")) || 0;
            const bid = parseFloat(startingBid.replace(/\D/g, "")) || price;
            payload = { customTitle: customTitle.trim(), customPrice: price, startingBid: bid };
        } else {
            if (!selectedAdId) { setError("Bir ilan seçin."); return; }
            const bid = parseFloat(adStartingBid.replace(/\D/g, "")) || 0;
            payload = { adId: selectedAdId, startingBid: bid };
        }

        setLoading(true);
        try {
            await onSubmit(payload);
            onClose();
        } catch (e: any) {
            setError(e?.message ?? "Sabitleme başarısız.");
        } finally {
            setLoading(false);
        }
    };

    if (!isOpen) return null;

    return (
        <div
            style={{
                position: "fixed", inset: 0, zIndex: 500,
                background: "rgba(0,0,0,0.65)", backdropFilter: "blur(6px)",
                display: "flex", alignItems: "center", justifyContent: "center",
            }}
            onClick={e => { if (e.target === e.currentTarget) onClose(); }}
        >
            <div style={{
                background: T.bg,
                border: `1px solid ${T.border}`,
                borderRadius: 20,
                width: "100%",
                maxWidth: 440,
                margin: "0 16px",
                display: "flex",
                flexDirection: "column",
                overflow: "hidden",
                boxShadow: "0 24px 80px rgba(0,0,0,0.7)",
            }}>
                {/* Header */}
                <div style={{
                    display: "flex", alignItems: "center", justifyContent: "space-between",
                    padding: "18px 20px 14px",
                    borderBottom: `1px solid ${T.border}`,
                }}>
                    <span style={{ fontFamily: T.display, fontWeight: 900, fontSize: 14, color: T.teal, letterSpacing: 1 }}>
                        📌 ÜRÜN SABİTLE
                    </span>
                    <button
                        onClick={onClose}
                        style={{
                            background: "none", border: "none", color: T.muted,
                            cursor: "pointer", fontSize: 18, lineHeight: 1,
                        }}
                    >
                        ✕
                    </button>
                </div>

                {/* Tabs */}
                <div style={{ display: "flex", borderBottom: `1px solid ${T.border}` }}>
                    {(["quick", "myads"] as const).map(t => (
                        <button
                            key={t}
                            onClick={() => setTab(t)}
                            style={{
                                flex: 1, padding: "12px 0",
                                background: "none",
                                border: "none",
                                borderBottom: tab === t ? `2px solid ${T.teal}` : "2px solid transparent",
                                color: tab === t ? T.teal : T.muted,
                                fontFamily: T.display, fontWeight: 700,
                                fontSize: 12, letterSpacing: 0.8,
                                cursor: "pointer", transition: "all 0.18s",
                            }}
                        >
                            {t === "quick" ? "⚡ HIZLI ÜRÜN" : "📋 İLANLARIM"}
                        </button>
                    ))}
                </div>

                {/* Body */}
                <div style={{ padding: "20px", display: "flex", flexDirection: "column", gap: 12 }}>

                    {tab === "quick" && (
                        <>
                            <div>
                                <label style={{ fontSize: 10, color: T.muted, fontFamily: T.display, fontWeight: 700, letterSpacing: 1 }}>
                                    ÜRÜN ADI *
                                </label>
                                <input
                                    ref={titleRef}
                                    style={{ ...inputStyle, marginTop: 6 }}
                                    placeholder="Örn: iPhone 14 Pro"
                                    value={customTitle}
                                    onChange={e => setCustomTitle(e.target.value)}
                                    onKeyDown={e => e.key === "Enter" && handleSubmit()}
                                />
                            </div>
                            <div style={{ display: "flex", gap: 10 }}>
                                <div style={{ flex: 1 }}>
                                    <label style={{ fontSize: 10, color: T.muted, fontFamily: T.display, fontWeight: 700, letterSpacing: 1 }}>
                                        ÜRÜN FİYATI (₺)
                                    </label>
                                    <input
                                        style={{ ...inputStyle, marginTop: 6 }}
                                        placeholder="0"
                                        value={customPrice}
                                        onChange={e => setCustomPrice(e.target.value.replace(/\D/g, ""))}
                                        inputMode="numeric"
                                    />
                                </div>
                                <div style={{ flex: 1 }}>
                                    <label style={{ fontSize: 10, color: T.muted, fontFamily: T.display, fontWeight: 700, letterSpacing: 1 }}>
                                        BAŞLANGIÇ TEKLİFİ (₺)
                                    </label>
                                    <input
                                        style={{ ...inputStyle, marginTop: 6 }}
                                        placeholder="Boş = fiyat"
                                        value={startingBid}
                                        onChange={e => setStartingBid(e.target.value.replace(/\D/g, ""))}
                                        inputMode="numeric"
                                    />
                                </div>
                            </div>
                        </>
                    )}

                    {tab === "myads" && (
                        <>
                            <div style={{
                                maxHeight: 260,
                                overflowY: "auto",
                                display: "flex",
                                flexDirection: "column",
                                gap: 8,
                            }}>
                                {adsLoading && (
                                    <p style={{ color: T.muted, fontFamily: T.display, fontSize: 12, textAlign: "center" }}>
                                        İlanlar yükleniyor...
                                    </p>
                                )}
                                {!adsLoading && adsList.length === 0 && (
                                    <p style={{ color: T.muted, fontFamily: T.display, fontSize: 12, textAlign: "center" }}>
                                        Aktif ilanınız bulunamadı.
                                    </p>
                                )}
                                {adsList.map(ad => (
                                    <div
                                        key={ad.id}
                                        onClick={() => setSelectedAdId(ad.id)}
                                        style={{
                                            display: "flex", alignItems: "center", gap: 12,
                                            padding: "10px 12px",
                                            borderRadius: 12,
                                            border: `1px solid ${selectedAdId === ad.id ? T.teal : T.border}`,
                                            background: selectedAdId === ad.id ? "rgba(6,200,224,0.08)" : T.inputBg,
                                            cursor: "pointer",
                                            transition: "all 0.15s",
                                        }}
                                    >
                                        {/* Thumbnail */}
                                        <div style={{
                                            width: 44, height: 44, borderRadius: 8,
                                            background: "rgba(255,255,255,0.05)",
                                            flexShrink: 0,
                                            overflow: "hidden",
                                            display: "flex", alignItems: "center", justifyContent: "center",
                                        }}>
                                            {ad.images[0] ? (
                                                <img
                                                    src={ad.images[0]}
                                                    alt={ad.title}
                                                    style={{ width: "100%", height: "100%", objectFit: "cover" }}
                                                />
                                            ) : (
                                                <span style={{ fontSize: 20 }}>📦</span>
                                            )}
                                        </div>
                                        <div style={{ flex: 1, minWidth: 0 }}>
                                            <div style={{
                                                fontSize: 12, fontWeight: 700, color: T.text,
                                                fontFamily: T.display,
                                                overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                                            }}>
                                                {ad.title}
                                            </div>
                                            <div style={{ fontSize: 11, color: T.teal, fontFamily: T.display, marginTop: 2 }}>
                                                ₺{(ad.price ?? ad.startingBid ?? 0).toLocaleString("tr-TR")}
                                            </div>
                                        </div>
                                        {selectedAdId === ad.id && (
                                            <span style={{ color: T.teal, fontSize: 16 }}>✓</span>
                                        )}
                                    </div>
                                ))}
                            </div>

                            {selectedAdId && (
                                <div>
                                    <label style={{ fontSize: 10, color: T.muted, fontFamily: T.display, fontWeight: 700, letterSpacing: 1 }}>
                                        BAŞLANGIÇ TEKLİFİ (₺) — Boş bırakılırsa ilan fiyatı kullanılır
                                    </label>
                                    <input
                                        style={{ ...inputStyle, marginTop: 6 }}
                                        placeholder="0"
                                        value={adStartingBid}
                                        onChange={e => setAdStartingBid(e.target.value.replace(/\D/g, ""))}
                                        inputMode="numeric"
                                    />
                                </div>
                            )}
                        </>
                    )}

                    {error && (
                        <p style={{ fontSize: 11, color: "#F03E3E", fontFamily: T.display, margin: 0 }}>{error}</p>
                    )}
                </div>

                {/* Footer */}
                <div style={{ padding: "0 20px 20px", display: "flex", gap: 10 }}>
                    <button
                        onClick={onClose}
                        style={{
                            flex: 1, padding: "11px 0", borderRadius: 12,
                            background: "none", border: `1px solid ${T.border}`,
                            color: T.muted, fontFamily: T.display, fontWeight: 700,
                            fontSize: 12, cursor: "pointer",
                        }}
                    >
                        İptal
                    </button>
                    <button
                        onClick={handleSubmit}
                        disabled={loading}
                        style={{
                            flex: 2, padding: "11px 0", borderRadius: 12,
                            background: loading ? "rgba(6,200,224,0.12)" : "rgba(6,200,224,0.18)",
                            border: `1px solid rgba(6,200,224,${loading ? 0.2 : 0.4})`,
                            color: loading ? T.muted : T.teal,
                            fontFamily: T.display, fontWeight: 900,
                            fontSize: 12, letterSpacing: 0.5,
                            cursor: loading ? "not-allowed" : "pointer",
                            transition: "all 0.18s",
                        }}
                    >
                        {loading ? "Sabitleniyor..." : "📌 Sahneye Sabitle"}
                    </button>
                </div>
            </div>
        </div>
    );
}
