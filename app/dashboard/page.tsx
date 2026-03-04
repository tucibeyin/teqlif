import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import DeleteAdButton from "./DeleteAdButton";
import RepublishAdButton from "./RepublishAdButton";
import DashboardSection from "./DashboardSection";

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
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);
    if (hours < 24) return `${hours} sa önce`;
    return `${days} gün önce`;
}

export default async function DashboardPage() {
    const session = await auth();
    if (!session?.user) redirect("/login");

    const [myAds, allMyBids, myFavorites] = await Promise.all([
        prisma.ad.findMany({
            where: { userId: session.user.id },
            orderBy: { createdAt: "desc" },
            include: {
                category: true,
                province: true,
                _count: { select: { bids: true } },
                bids: {
                    where: { status: { in: ['PENDING', 'ACCEPTED'] } },
                    orderBy: { amount: "desc" },
                    take: 1,
                    select: { amount: true }
                }
            },
        }),
        prisma.bid.findMany({
            where: { userId: session.user.id },
            orderBy: { amount: "desc" }, // Sort by amount desc to easily pick highest
            include: {
                ad: {
                    include: {
                        category: true,
                        province: true,
                    },
                },
            },
        }),
        prisma.favorite.findMany({
            where: { userId: session.user.id },
            orderBy: { createdAt: "desc" },
            include: {
                ad: {
                    include: {
                        category: true,
                        province: true,
                        _count: { select: { bids: true } }
                    },
                },
            },
        })
    ]);

    // Unique bids: Only show the highest bid per advertisement
    const uniqueBidsMap = new Map();
    allMyBids.forEach((bid) => {
        if (!uniqueBidsMap.has(bid.adId)) {
            uniqueBidsMap.set(bid.adId, bid);
        }
    });
    const myBids = Array.from(uniqueBidsMap.values());

    const totalBidsReceived = myAds.reduce((sum: number, ad: any) => sum + ad._count.bids, 0);

    return (
        <div className="dashboard">
            <div className="container">
                <div className="dashboard-header">
                    <div>
                        <h1 className="dashboard-name">
                            Merhaba, <span>{session.user.name?.split(" ")[0]}</span> 👋
                        </h1>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginTop: "0.5rem" }}>
                            <p className="text-muted text-sm" style={{ margin: 0 }}>{session.user.email}</p>
                            <Link href="/dashboard/profile" style={{ fontSize: "0.85rem", color: "var(--primary)", textDecoration: "underline", fontWeight: 500 }}>
                                Profilimi Düzenle
                            </Link>
                        </div>
                    </div>
                    <Link href="/post-ad" className="btn btn-primary">
                        + Yeni İlan Ver
                    </Link>
                </div>

                {/* Stats */}
                <div className="stats-grid">
                    <Link href="#ilanlarim" className="stat-card" style={{ textDecoration: 'none', color: 'inherit', display: 'flex', flexDirection: 'column' }}>
                        <div className="stat-value">{myAds.length}</div>
                        <div className="stat-label">Aktif İlanım</div>
                    </Link>
                    <Link href="#ilanlarim" className="stat-card" style={{ textDecoration: 'none', color: 'inherit', display: 'flex', flexDirection: 'column' }}>
                        <div className="stat-value">{totalBidsReceived}</div>
                        <div className="stat-label">Gelen Teqlif</div>
                    </Link>
                    <Link href="#teqliflerim" className="stat-card" style={{ textDecoration: 'none', color: 'inherit', display: 'flex', flexDirection: 'column' }}>
                        <div className="stat-value">{myBids.length}</div>
                        <div className="stat-label">Verdiğim Teqlif</div>
                    </Link>
                    <Link href="#favorilerim" className="stat-card" style={{ textDecoration: 'none', color: 'inherit', display: 'flex', flexDirection: 'column' }}>
                        <div className="stat-value" style={{ color: "var(--accent-red)" }}>{myFavorites.length}</div>
                        <div className="stat-label">Favorilerim</div>
                    </Link>
                    <Link href="/dashboard/friends" className="stat-card" style={{ textDecoration: 'none', color: 'inherit', display: 'flex', flexDirection: 'column' }}>
                        <div className="stat-value" style={{ color: "var(--primary)" }}>👥</div>
                        <div className="stat-label">Arkadaşlarım</div>
                    </Link>
                    <Link href="#ilanlarim" className="stat-card" style={{ textDecoration: 'none', color: 'inherit', display: 'flex', flexDirection: 'column' }}>
                        <div className="stat-value" style={{ color: "var(--accent-green)" }}>
                            {myAds.filter((a: any) => a.status === "ACTIVE" && (!a.expiresAt || new Date(a.expiresAt) > new Date())).length}
                        </div>
                        <div className="stat-label">Aktif</div>
                    </Link>
                </div>

                {/* İlanlarım */}
                <DashboardSection title="İlanlarım" id="ilanlarim" count={myAds.length} defaultExpanded={true}>
                    {myAds.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-state-icon">📭</div>
                            <div className="empty-state-title">Henüz ilan vermediniz</div>
                            <p>İlk ilanınızı hemen ekleyin!</p>
                            <Link href="/post-ad" className="btn btn-primary" style={{ marginTop: "1rem" }}>
                                İlan Ver
                            </Link>
                        </div>
                    ) : (
                        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                            {myAds.map((ad: any) => {
                                const isExpired = ad.expiresAt ? new Date(ad.expiresAt) < new Date() : false;
                                return (
                                    <div key={ad.id} className="card">
                                        <div className="card-body" style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                            {ad.images && ad.images.length > 0 ? (
                                                <Image src={ad.images[0]} alt={ad.title} width={48} height={48} style={{ objectFit: "cover", borderRadius: "10px" }} />
                                            ) : (
                                                <span style={{ fontSize: "2rem" }}>{ad.category.icon}</span>
                                            )}
                                            <div style={{ flex: 1 }}>
                                                <Link href={`/ad/${ad.id}`} style={{ color: "var(--text-primary)", fontWeight: 600, fontSize: "0.9375rem" }}>
                                                    {ad.title}
                                                </Link>
                                                <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                                    {ad.province.name} · {timeAgo(ad.createdAt)} · {ad._count.bids} teqlif
                                                </div>
                                            </div>
                                            <div style={{ textAlign: "right", display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "0.5rem" }}>
                                                <div style={{ color: "var(--primary)", fontWeight: 700 }}>
                                                    {(() => {
                                                        if (ad.isFixedPrice) return formatPrice(ad.price);
                                                        const highestBid = ad.bids?.[0]?.amount;
                                                        if (highestBid) return formatPrice(highestBid);
                                                        return ad.startingBid ? formatPrice(ad.startingBid) : "Serbest Teqlif";
                                                    })()}
                                                </div>
                                                <span className={`badge badge-${isExpired ? 'expired' : ad.status.toLowerCase()}`}>
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
                </DashboardSection>

                {/* Favorilerim */}
                <DashboardSection title="Favorilerim" id="favorilerim" count={myFavorites.length}>
                    {myFavorites.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-state-icon">❤️‍🩹</div>
                            <div className="empty-state-title">Henüz favori ilanınız yok</div>
                            <p>İlgilinizi çeken ilanları favorilere ekleyin!</p>
                            <Link href="/" className="btn btn-outline" style={{ marginTop: "1rem" }}>
                                İlanlara Bak
                            </Link>
                        </div>
                    ) : (
                        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                            {myFavorites.map((fav: any) => {
                                const ad = fav.ad;
                                const isExpired = ad.expiresAt ? new Date(ad.expiresAt) < new Date() : false;
                                return (
                                    <div key={fav.id} className="card">
                                        <div className="card-body" style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                            {ad.images && ad.images.length > 0 ? (
                                                <Image src={ad.images[0]} alt={ad.title} width={48} height={48} style={{ objectFit: "cover", borderRadius: "10px" }} />
                                            ) : (
                                                <span style={{ fontSize: "2rem" }}>{ad.category.icon}</span>
                                            )}
                                            <div style={{ flex: 1 }}>
                                                <Link href={`/ad/${ad.id}`} style={{ color: "var(--text-primary)", fontWeight: 600, fontSize: "0.9375rem" }}>
                                                    {ad.title}
                                                </Link>
                                                <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                                    {ad.province.name} · {timeAgo(ad.createdAt)} · {ad._count.bids} teqlif
                                                </div>
                                            </div>
                                            <div style={{ textAlign: "right", display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "0.5rem" }}>
                                                <div style={{ color: "var(--primary)", fontWeight: 700 }}>{formatPrice(ad.price)}</div>
                                                <span className={`badge badge-${isExpired ? 'expired' : ad.status.toLowerCase()}`}>
                                                    {isExpired ? "Süresi Dolmuş" : ad.status === "ACTIVE" ? "Aktif" : ad.status === "SOLD" ? "Satıldı" : "Pasif"}
                                                </span>
                                            </div>
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    )}
                </DashboardSection>

                {/* Verdiğim Teqlifler */}
                <DashboardSection title="Verdiğim Teqlifler" id="teqliflerim" count={myBids.length}>
                    {myBids.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-state-icon">🔨</div>
                            <div className="empty-state-title">Henüz teqlif vermediniz</div>
                            <p>İlanlara göz atın ve teqlif verin!</p>
                            <Link href="/" className="btn btn-outline" style={{ marginTop: "1rem" }}>
                                İlanlara Bak
                            </Link>
                        </div>
                    ) : (
                        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                            {myBids.map((bid: any) => (
                                <div key={bid.id} className="card">
                                    <div className="card-body" style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                        {bid.ad.images && bid.ad.images.length > 0 ? (
                                            <Image src={bid.ad.images[0]} alt={bid.ad.title} width={48} height={48} style={{ objectFit: "cover", borderRadius: "10px" }} />
                                        ) : (
                                            <span style={{ fontSize: "2rem" }}>{bid.ad.category.icon}</span>
                                        )}
                                        <div style={{ flex: 1 }}>
                                            <Link href={`/ad/${bid.adId}`} style={{ color: "var(--text-primary)", fontWeight: 600, fontSize: "0.9375rem" }}>
                                                {bid.ad.title}
                                            </Link>
                                            <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                                {bid.ad.province.name} · {timeAgo(bid.createdAt)}
                                            </div>
                                        </div>
                                        <div style={{ textAlign: "right" }}>
                                            <div style={{ color: "var(--primary)", fontWeight: 700 }}>
                                                Teqlifim: {formatPrice(bid.amount)}
                                            </div>
                                            <div className="text-muted text-sm">
                                                İlan: {formatPrice(bid.ad.price)}
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </DashboardSection>
            </div >
        </div >
    );
}
