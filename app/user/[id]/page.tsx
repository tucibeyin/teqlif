"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import { useSession } from "next-auth/react";


export default function UserProfilePage() {
    const { id } = useParams();
    const router = useRouter();
    const { data: session } = useSession();

    const [loading, setLoading] = useState(true);
    const [actionLoading, setActionLoading] = useState(false);
    const [user, setUser] = useState<any>(null);
    const [ads, setAds] = useState<any[]>([]);
    const [connectionStatus, setConnectionStatus] = useState<"NONE" | "FRIEND" | "SELF" | "BLOCKED_BY_ME" | "BLOCKED_BY_THEM">("NONE");

    // For report dialog
    const [showReportDialog, setShowReportDialog] = useState(false);
    const [reportReason, setReportReason] = useState("");

    // For friend list management
    const [lists, setLists] = useState<any[]>([]);
    const [currentListId, setCurrentListId] = useState<string>("null");

    useEffect(() => {
        const fetchProfile = async () => {
            try {
                const res = await fetch(`/api/users/${id}`);
                const data = await res.json();

                if (res.ok) {
                    setUser(data.user);
                    setAds(data.ads);
                    setConnectionStatus(data.connectionStatus);

                    if (data.connectionStatus === "FRIEND") {
                        const fRes = await fetch("/api/users/friends");
                        if (fRes.ok) {
                            const fData = await fRes.json();
                            setLists(fData.customLists || []);
                            const fInfo = fData.friends?.find((f: any) => f.id === id);
                            if (fInfo) setCurrentListId(fInfo.friendListId || "null");
                        }
                    }
                } else {
                    alert(data.error || "Kullanıcı bulunamadı.");
                    router.push("/");
                }
            } catch (e) {
                console.error("Profile fetch error:", e);
                alert("Bir hata oluştu.");
            } finally {
                setLoading(false);
            }
        };

        if (id) fetchProfile();
    }, [id, router]);

    const handleFollowToggle = async () => {
        if (!session) {
            router.push("/login");
            return;
        }

        setActionLoading(true);
        try {
            if (connectionStatus === "FRIEND") {
                const res = await fetch(`/api/users/friends/${id}`, { method: "DELETE" });
                if (res.ok) setConnectionStatus("NONE");
            } else {
                const res = await fetch(`/api/users/friends`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ targetUserId: id })
                });
                if (res.ok) {
                    setConnectionStatus("FRIEND");
                    const fRes = await fetch("/api/users/friends");
                    if (fRes.ok) {
                        const fData = await fRes.json();
                        setLists(fData.customLists || []);
                    }
                }
            }
        } catch (e) {
            console.error("Follow error:", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleMessage = async () => {
        if (!session) {
            router.push("/login");
            return;
        }

        setActionLoading(true);
        try {
            const res = await fetch("/api/conversations", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ userId: id })
            });

            if (res.ok) {
                const conversation = await res.json();
                router.push(`/dashboard/messages?id=${conversation.id}`);
            }
        } catch (e) {
            console.error("Message initiation error", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleListChange = async (newListId: string) => {
        try {
            const res = await fetch(`/api/users/friend-lists/${newListId}`, {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ friendId: id })
            });
            if (res.ok) setCurrentListId(newListId);
        } catch (e) {
            console.error(e);
        }
    };

    const handleBlockToggle = async () => {
        if (!session) {
            router.push("/login");
            return;
        }

        setActionLoading(true);
        try {
            if (connectionStatus === "BLOCKED_BY_ME") {
                const res = await fetch(`/api/users/block?userId=${id}`, { method: "DELETE" });
                if (res.ok) setConnectionStatus("NONE");
            } else {
                if (window.confirm("Bu kullanıcıyı engellemek istediğinize emin misiniz?")) {
                    const res = await fetch(`/api/users/block`, {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ targetUserId: id })
                    });
                    if (res.ok) setConnectionStatus("BLOCKED_BY_ME");
                }
            }
        } catch (e) {
            console.error("Block error:", e);
        } finally {
            setActionLoading(false);
        }
    };

    const handleReport = async () => {
        if (!session) {
            router.push("/login");
            return;
        }

        if (!reportReason.trim()) {
            alert("Lütfen şikayet nedeninizi belirtin.");
            return;
        }

        setActionLoading(true);
        try {
            const res = await fetch(`/api/reports`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ reason: reportReason, reportedUserId: id })
            });

            if (res.ok) {
                alert("Şikayetiniz alınmıştır. Teşekkür ederiz.");
                setShowReportDialog(false);
                setReportReason("");
            } else {
                alert("Şikayet gönderilemedi.");
            }
        } catch (e) {
            console.error("Report error:", e);
        } finally {
            setActionLoading(false);
        }
    };

    if (loading) {
        return (
            <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <div style={{ width: '48px', height: '48px', border: '4px solid var(--primary)', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 1s linear infinite' }}></div>
                <style>{`@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }`}</style>
            </div>
        );
    }

    if (!user) return null;

    return (
        <div style={{ padding: '3rem 0', minHeight: '100vh', backgroundColor: 'var(--bg)' }}>
            <div className="container" style={{ maxWidth: '960px' }}>

                {/* Profile Header */}
                <div className="card" style={{ padding: '2rem', marginBottom: '2.5rem' }}>
                    <div style={{ display: 'flex', gap: '2.5rem', alignItems: 'center', flexWrap: 'wrap' }}>

                        {/* Avatar */}
                        <div style={{ width: '120px', height: '120px', borderRadius: '50%', overflow: 'hidden', border: '4px solid var(--border-light)', backgroundColor: 'var(--bg)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                            {user.avatar ? (
                                <Image src={user.avatar} alt={user.name} width={120} height={120} style={{ objectFit: 'cover' }} />
                            ) : (
                                <span style={{ fontSize: '3rem', fontWeight: 800, color: 'var(--text-muted)' }}>{user.name.charAt(0).toUpperCase()}</span>
                            )}
                        </div>

                        {/* Info */}
                        <div style={{ flex: 1, minWidth: '280px' }}>
                            <h1 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--text-primary)', marginBottom: '0.25rem' }}>{user.name}</h1>
                            <p style={{ color: 'var(--text-secondary)', marginBottom: '1rem', fontSize: '0.9375rem' }}>
                                teqlif Üyesi • {new Date(user.createdAt).toLocaleDateString("tr-TR", { year: 'numeric', month: 'long' })} tarihinden beri
                            </p>

                            {user.phone && (
                                <div style={{ display: 'inline-flex', alignItems: 'center', backgroundColor: 'var(--bg-input)', padding: '0.5rem 1rem', borderRadius: 'var(--radius-full)', fontSize: '0.875rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: '1.5rem' }}>
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: '0.5rem', color: 'var(--primary)' }}><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path></svg>
                                    {user.phone}
                                </div>
                            )}

                            {/* Actions */}
                            {connectionStatus !== "SELF" && connectionStatus !== "BLOCKED_BY_THEM" && (
                                <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap', alignItems: 'center' }}>

                                    {connectionStatus !== "BLOCKED_BY_ME" && (
                                        <>
                                            <button
                                                onClick={handleFollowToggle}
                                                disabled={actionLoading}
                                                className={connectionStatus === "FRIEND" ? "btn btn-secondary" : "btn btn-primary"}
                                                style={{ minWidth: '140px' }}
                                            >
                                                {actionLoading ? "İşleniyor..." : connectionStatus === "FRIEND" ? "Takipten Çık" : "Takip Et"}
                                            </button>

                                            {connectionStatus === "FRIEND" && (
                                                <select
                                                    value={currentListId}
                                                    onChange={(e) => handleListChange(e.target.value)}
                                                    className="input"
                                                    style={{ width: '160px', borderRadius: 'var(--radius-full)', padding: '0.5rem 2rem 0.5rem 1rem', fontSize: '0.875rem' }}
                                                >
                                                    <option value="null">⭐ Listesiz</option>
                                                    {lists.map(l => (
                                                        <option key={l.id} value={l.id}>{l.name}</option>
                                                    ))}
                                                </select>
                                            )}

                                            <button
                                                onClick={handleMessage}
                                                disabled={actionLoading}
                                                className="btn btn-outline"
                                            >
                                                Mesaj Gönder
                                            </button>
                                        </>
                                    )}

                                    <button
                                        onClick={handleBlockToggle}
                                        disabled={actionLoading}
                                        className="btn btn-outline"
                                        style={{ color: connectionStatus === "BLOCKED_BY_ME" ? 'var(--text-primary)' : 'var(--danger)', borderColor: connectionStatus === "BLOCKED_BY_ME" ? 'var(--border)' : 'var(--danger)' }}
                                    >
                                        {actionLoading ? "İşleniyor..." : connectionStatus === "BLOCKED_BY_ME" ? "Engeli Kaldır" : "Kullanıcıyı Engelle"}
                                    </button>

                                    {connectionStatus !== "BLOCKED_BY_ME" && (
                                        <button
                                            onClick={() => setShowReportDialog(true)}
                                            className="btn btn-outline"
                                            style={{ color: 'var(--text-muted)', border: 'none' }}
                                        >
                                            Şikayet Et
                                        </button>
                                    )}
                                </div>
                            )}

                            {connectionStatus === "BLOCKED_BY_THEM" && (
                                <p style={{ color: 'var(--danger)', fontWeight: 'bold' }}>Bu kullanıcının profiline erişiminiz kısıtlanmıştır.</p>
                            )}
                        </div>

                        {/* Stats box (Hidden if blocked) */}
                        {connectionStatus !== "BLOCKED_BY_ME" && connectionStatus !== "BLOCKED_BY_THEM" && (
                            <div style={{ display: 'flex', gap: '2rem', padding: '1.5rem', backgroundColor: 'var(--bg-input)', borderRadius: 'var(--radius-lg)', border: '1px solid var(--border)' }}>
                                <div style={{ textAlign: 'center' }}>
                                    <div style={{ fontSize: '1.75rem', fontWeight: 900, color: 'var(--text-primary)', lineHeight: 1 }}>{user.stats.activeAds}</div>
                                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', marginTop: '0.5rem', letterSpacing: '0.05em' }}>Aktif İlan</div>
                                </div>
                                <div style={{ width: '1px', backgroundColor: 'var(--border)' }}></div>
                                <div style={{ textAlign: 'center' }}>
                                    <div style={{ fontSize: '1.75rem', fontWeight: 900, color: 'var(--text-primary)', lineHeight: 1 }}>{user.stats.followers}</div>
                                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', marginTop: '0.5rem', letterSpacing: '0.05em' }}>Takipçi</div>
                                </div>
                            </div>
                        )}

                    </div>
                </div>

                {/* Ads Section (Hidden if blocked) */}
                {connectionStatus !== "BLOCKED_BY_ME" && connectionStatus !== "BLOCKED_BY_THEM" && (
                    <div>
                        <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--text-primary)', marginBottom: '1.5rem' }}>
                            Kullanıcının İlanları
                        </h2>

                        {ads.length === 0 ? (
                            <div className="card" style={{ padding: '3rem 2rem', textAlign: 'center' }}>
                                <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>📭</div>
                                <p style={{ color: 'var(--text-secondary)', fontSize: '1.125rem' }}>Bu kullanıcının henüz aktif bir ilanı bulunmuyor.</p>
                            </div>
                        ) : (
                            <div className="ads-grid">
                                {ads.map((ad: any) => (
                                    <Link
                                        href={`/ad/${ad.id}`}
                                        key={ad.id}
                                        className="ad-card"
                                    >
                                        <div style={{ position: 'relative' }}>
                                            {ad.images && ad.images.length > 0 ? (
                                                <img
                                                    src={ad.images[0]}
                                                    alt={ad.title}
                                                    className="ad-card-image"
                                                />
                                            ) : (
                                                <div className="ad-card-image-placeholder">📷</div>
                                            )}
                                            {/* Status Badge */}
                                            <div style={{ position: 'absolute', top: '0.75rem', right: '0.75rem', backgroundColor: 'rgba(255,255,255,0.9)', padding: '0.25rem 0.75rem', borderRadius: '1rem', fontSize: '0.75rem', fontWeight: 700, boxShadow: 'var(--shadow-sm)' }}>
                                                {ad.isAuction ? (
                                                    <span style={{ color: 'var(--accent-orange)' }}>
                                                        Açık Arttırma
                                                    </span>
                                                ) : (
                                                    <span style={{ color: 'var(--primary)' }}>Sabit Fiyat</span>
                                                )}
                                            </div>
                                        </div>

                                        <div className="ad-card-body" style={{ display: 'flex', flexDirection: 'column', height: '110px' }}>
                                            <h3 className="ad-card-title">
                                                {ad.title}
                                            </h3>
                                            <div style={{ marginTop: 'auto', paddingTop: '0.75rem', borderTop: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
                                                <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                                                    {ad.province?.name} / {ad.district?.name}
                                                </div>
                                                <div style={{ fontSize: '1.125rem', fontWeight: 900, color: 'var(--text-primary)' }}>
                                                    {new Intl.NumberFormat("tr-TR").format(ad.price)} ₺
                                                </div>
                                            </div>
                                        </div>
                                    </Link>
                                ))}
                            </div>
                        )}
                    </div>
                )}

                {/* Report Dialog Modal */}
                {showReportDialog && (
                    <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000, padding: '1rem' }}>
                        <div className="card" style={{ padding: '2rem', width: '100%', maxWidth: '400px' }}>
                            <h3 style={{ fontSize: '1.25rem', fontWeight: 'bold', marginBottom: '1rem' }}>Kullanıcıyı Şikayet Et</h3>
                            <p style={{ fontSize: '0.875rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>Lütfen bu kullanıcıyı neden şikayet ettiğinizi kısaca açıklayın.</p>
                            <textarea
                                value={reportReason}
                                onChange={(e) => setReportReason(e.target.value)}
                                className="input"
                                rows={4}
                                placeholder="Şikayet nedeni..."
                                style={{ width: '100%', resize: 'vertical', marginBottom: '1rem' }}
                            ></textarea>
                            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '1rem' }}>
                                <button className="btn btn-outline" onClick={() => setShowReportDialog(false)} disabled={actionLoading}>İptal</button>
                                <button className="btn btn-primary" onClick={handleReport} disabled={actionLoading} style={{ backgroundColor: 'var(--danger)', borderColor: 'var(--danger)' }}>{actionLoading ? 'Gönderiliyor...' : 'Şikayet Et'}</button>
                            </div>
                        </div>
                    </div>
                )}

            </div>
        </div>
    );
}
