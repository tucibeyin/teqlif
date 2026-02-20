import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";
import Link from "next/link";
import { redirect } from "next/navigation";
import DeleteAdButton from "./DeleteAdButton";

function formatPrice(price: number) {
    return new Intl.NumberFormat("tr-TR", {
        style: "currency",
        currency: "TRY",
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
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

    const [myAds, myBids] = await Promise.all([
        prisma.ad.findMany({
            where: { userId: session.user.id },
            orderBy: { createdAt: "desc" },
            include: {
                category: true,
                province: true,
                _count: { select: { bids: true } },
            },
        }),
        prisma.bid.findMany({
            where: { userId: session.user.id },
            orderBy: { createdAt: "desc" },
            take: 20,
            include: {
                ad: {
                    include: {
                        category: true,
                        province: true,
                    },
                },
            },
        }),
    ]);

    const totalBidsReceived = myAds.reduce((sum, ad) => sum + ad._count.bids, 0);

    return (
        <div className="dashboard">
            <div className="container">
                <div className="dashboard-header">
                    <div>
                        <h1 className="dashboard-name">
                            Merhaba, <span>{session.user.name?.split(" ")[0]}</span> 👋
                        </h1>
                        <p className="text-muted text-sm">{session.user.email}</p>
                    </div>
                    <Link href="/post-ad" className="btn btn-primary">
                        + Yeni İlan Ver
                    </Link>
                </div>

                {/* Stats */}
                <div className="stats-grid">
                    <div className="stat-card">
                        <div className="stat-value">{myAds.length}</div>
                        <div className="stat-label">Aktif İlanım</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-value">{totalBidsReceived}</div>
                        <div className="stat-label">Gelen Teklif</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-value">{myBids.length}</div>
                        <div className="stat-label">Verdiğim Teklif</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-value" style={{ color: "var(--accent-green)" }}>
                            {myAds.filter((a) => a.status === "ACTIVE").length}
                        </div>
                        <div className="stat-label">Aktif</div>
                    </div>
                </div>

                {/* İlanlarım */}
                <section className="section">
                    <div className="section-header">
                        <h2 className="section-title">İlanlarım</h2>
                    </div>

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
                            {myAds.map((ad) => (
                                <div key={ad.id} className="card">
                                    <div className="card-body" style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                        {ad.images && ad.images.length > 0 ? (
                                            <img src={ad.images[0]} alt={ad.title} style={{ width: "48px", height: "48px", objectFit: "cover", borderRadius: "10px" }} />
                                        ) : (
                                            <span style={{ fontSize: "2rem" }}>{ad.category.icon}</span>
                                        )}
                                        <div style={{ flex: 1 }}>
                                            <Link href={`/ad/${ad.id}`} style={{ color: "var(--text-primary)", fontWeight: 600, fontSize: "0.9375rem" }}>
                                                {ad.title}
                                            </Link>
                                            <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                                {ad.province.name} · {timeAgo(ad.createdAt)} · {ad._count.bids} teklif
                                            </div>
                                        </div>
                                        <div style={{ textAlign: "right", display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "0.5rem" }}>
                                            <div style={{ color: "var(--primary)", fontWeight: 700 }}>{formatPrice(ad.price)}</div>
                                            <span className={`badge badge-${ad.status.toLowerCase()}`}>
                                                {ad.status === "ACTIVE" ? "Aktif" : ad.status === "SOLD" ? "Satıldı" : "Süresi Dolmuş"}
                                            </span>
                                            <div style={{ display: "flex", gap: "0.5rem", marginTop: "0.5rem" }}>
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
                                                <DeleteAdButton id={ad.id} />
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </section>

                {/* Verdiğim Teklifler */}
                <section className="section">
                    <div className="section-header">
                        <h2 className="section-title">Verdiğim Teklifler</h2>
                    </div>

                    {myBids.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-state-icon">🔨</div>
                            <div className="empty-state-title">Henüz teklif vermediniz</div>
                            <p>İlanlara göz atın ve teklif verin!</p>
                            <Link href="/" className="btn btn-outline" style={{ marginTop: "1rem" }}>
                                İlanlara Bak
                            </Link>
                        </div>
                    ) : (
                        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                            {myBids.map((bid) => (
                                <div key={bid.id} className="card">
                                    <div className="card-body" style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                                        {bid.ad.images && bid.ad.images.length > 0 ? (
                                            <img src={bid.ad.images[0]} alt={bid.ad.title} style={{ width: "48px", height: "48px", objectFit: "cover", borderRadius: "10px" }} />
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
                                                Teklifim: {formatPrice(bid.amount)}
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
                </section>
            </div>
        </div>
    );
}
