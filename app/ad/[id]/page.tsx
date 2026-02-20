import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { notFound } from "next/navigation";
import Link from "next/link";
import BidForm from "./BidForm";
import ImageSlider from "./ImageSlider";
import { AdActions } from "./AdActions";

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
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);
    if (minutes < 60) return `${minutes} dk önce`;
    if (hours < 24) return `${hours} sa önce`;
    return `${days} gün önce`;
}

export default async function AdDetailPage({
    params,
}: {
    params: Promise<{ id: string }>;
}) {
    const { id } = await params;
    const session = await auth();

    const ad = await prisma.ad.findUnique({
        where: { id },
        include: {
            user: { select: { id: true, name: true, phone: true } },
            category: true,
            province: true,
            district: true,
            bids: {
                orderBy: { amount: "desc" },
                take: 10,
                include: { user: { select: { id: true, name: true } } },
            },
        },
    });

    if (!ad) notFound();

    const highestBid = ad.bids[0];
    const isOwner = session?.user?.id === ad.userId;

    return (
        <div className="container">
            <div className="ad-detail">
                {/* Sol: Görsel ve Detay */}
                <div>
                    <div className="ad-detail-images">
                        {ad.images && ad.images.length > 0 ? (
                            <ImageSlider images={ad.images} title={ad.title} />
                        ) : (
                            <div
                                style={{
                                    width: "100%",
                                    height: "400px",
                                    background: "linear-gradient(135deg, var(--bg-secondary), var(--bg-card-hover))",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    fontSize: "6rem",
                                    borderRadius: "var(--radius-lg)",
                                    border: "1px solid var(--border)",
                                }}
                            >
                                {ad.category.icon}
                            </div>
                        )}
                    </div>

                    {/* İlan Detayları */}
                    <div className="card" style={{ marginTop: "1.5rem" }}>
                        <div className="card-body">
                            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "1rem" }}>
                                <div>
                                    <span className="ad-card-badge">{ad.category.icon} {ad.category.name}</span>
                                </div>
                                <span className="text-muted text-sm">{timeAgo(ad.createdAt)}</span>
                            </div>

                            <h1 style={{ fontSize: "1.5rem", fontWeight: 700, marginBottom: "0.75rem" }}>{ad.title}</h1>

                            <div style={{ display: "flex", gap: "1rem", marginBottom: "1.25rem", color: "var(--text-secondary)", fontSize: "0.9rem" }}>
                                <span>📍 {ad.province.name}, {ad.district.name}</span>
                                <span>👤 {ad.user.name}</span>
                            </div>

                            <div style={{
                                background: "var(--bg-secondary)",
                                borderRadius: "var(--radius-md)",
                                padding: "1.25rem",
                                lineHeight: "1.7",
                                color: "var(--text-secondary)",
                                whiteSpace: "pre-wrap",
                            }}>
                                {ad.description}
                            </div>

                            {!isOwner && session?.user && (
                                <div style={{ marginTop: "1.25rem", display: "flex", gap: "1rem", flexDirection: "column" }}>
                                    {ad.user.phone && (
                                        <a
                                            href={`tel:${ad.user.phone}`}
                                            className="btn btn-secondary btn-full"
                                        >
                                            📞 {ad.user.phone} - Satıcıyı Ara
                                        </a>
                                    )}
                                    <AdActions
                                        actionType="MESSAGE"
                                        adId={ad.id}
                                        sellerId={ad.userId}
                                        currentUser={session.user}
                                        initialMessage={`"${ad.title}" (İlan No: ${ad.id}) ilanı hakkında bilgi almak istiyorum.`}
                                    />
                                </div>
                            )}
                            {!isOwner && !session?.user && ad.user.phone && (
                                <div style={{ marginTop: "1.25rem" }}>
                                    <a
                                        href={`tel:${ad.user.phone}`}
                                        className="btn btn-secondary btn-full"
                                    >
                                        📞 {ad.user.phone} - Satıcıyı Ara
                                    </a>
                                </div>
                            )}
                        </div>
                    </div>
                </div>

                {/* Sağ: Açık Artırma */}
                <div>
                    <div className="auction-card">
                        <div style={{ marginBottom: "1.25rem" }}>
                            <div className="auction-label">
                                {ad.startingBid === null ? "Açılış (Serbest Teklif)" : "Minimum Açılış Teklifi"}
                            </div>
                            <div style={{ fontSize: "1.25rem", fontWeight: 600, color: "var(--text-secondary)" }}>
                                {ad.startingBid === null ? formatPrice(1) : formatPrice(ad.startingBid)}
                            </div>
                            <div className="text-muted" style={{ fontSize: "0.875rem", marginTop: "0.25rem" }}>
                                Piyasa Değeri: <span style={{ textDecoration: "line-through" }}>{formatPrice(ad.price)}</span>
                            </div>
                        </div>

                        {highestBid && (
                            <div style={{ marginBottom: "1.25rem" }}>
                                <div className="auction-label">En Yüksek Teklif</div>
                                <div className="auction-current-price">
                                    {formatPrice(highestBid.amount)}
                                </div>
                                <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                    {highestBid.user.name} tarafından
                                </div>
                            </div>
                        )}

                        <div style={{ display: "flex", gap: "0.5rem", marginBottom: "1.25rem" }}>
                            <div style={{
                                background: "rgba(0, 188, 212, 0.08)",
                                border: "1px solid rgba(0, 188, 212, 0.2)",
                                borderRadius: "var(--radius-md)",
                                padding: "0.5rem 0.875rem",
                                flex: 1,
                                textAlign: "center",
                            }}>
                                <div style={{ fontWeight: 700, color: "var(--primary)" }}>{ad.bids.length}</div>
                                <div className="text-muted" style={{ fontSize: "0.75rem" }}>Teklif</div>
                            </div>
                            <div style={{
                                background: "rgba(0, 188, 212, 0.08)",
                                border: "1px solid rgba(0, 188, 212, 0.2)",
                                borderRadius: "var(--radius-md)",
                                padding: "0.5rem 0.875rem",
                                flex: 1,
                                textAlign: "center",
                            }}>
                                <span className={`badge badge-${ad.status.toLowerCase()}`}>
                                    {ad.status === "ACTIVE" ? "Aktif" : ad.status === "SOLD" ? "Satıldı" : "Süresi Doldu"}
                                </span>
                            </div>
                        </div>

                        {/* Teklif Formu */}
                        {!isOwner && session?.user ? (
                            <BidForm
                                adId={ad.id}
                                currentHighest={highestBid?.amount ?? (ad.startingBid !== null ? ad.startingBid : 0)} // If no bids and free bid, it acts as 0. So next minimum is 0 + minStep(1) = 1
                                minStep={ad.bids.length > 0 ? ad.minBidStep : (ad.startingBid === null ? 1 : 0)} // If first bid and exact startingBid, minStep is 0 to allow exact startingBid amount
                            />
                        ) : !session?.user ? (
                            <div style={{ textAlign: "center", padding: "1.5rem 0", border: "1px dashed var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg-card-hover)" }}>
                                <p className="text-muted text-sm" style={{ marginBottom: "0.75rem" }}>
                                    Bu ilana teklif vermek için giriş yapmalısınız.
                                </p>
                                <Link href="/login" className="btn btn-primary btn-full">
                                    Giriş Yap
                                </Link>
                            </div>
                        ) : (
                            <div style={{ textAlign: "center", padding: "1.25rem", background: "var(--primary-50)", borderRadius: "var(--radius-md)", color: "var(--primary-dark)", border: "1px solid var(--primary-100)" }}>
                                <strong style={{ display: "block", marginBottom: "0.25rem" }}>Bu ilan size ait</strong>
                                Kendi ilanınıza teklif veremezsiniz. Başkalarının teklif vermesini bekleyin.
                            </div>
                        )}

                        {/* Teklif Geçmişi */}
                        {ad.bids.length > 0 && (
                            <div className="bid-history">
                                <div style={{ fontWeight: 600, fontSize: "0.875rem", marginBottom: "0.5rem" }}>
                                    Teklif Geçmişi
                                </div>
                                {ad.bids.map((bid, i) => (
                                    <div key={bid.id} className="bid-item" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                        <div>
                                            <span className="bid-item-user">
                                                {i === 0 && "🏆 "}
                                                {bid.user.name}
                                            </span>
                                            <span className="bid-item-amount" style={{ marginLeft: '8px' }}>{formatPrice(bid.amount)}</span>
                                        </div>
                                        {isOwner && (
                                            <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                                                {bid.status === 'PENDING' && (
                                                    <AdActions actionType="ACCEPT_BID" bidId={bid.id} currentUser={session?.user} />
                                                )}
                                                <AdActions
                                                    actionType="MESSAGE"
                                                    adId={ad.id}
                                                    sellerId={bid.user.id}
                                                    currentUser={session?.user}
                                                    isMessageBidder={true}
                                                    initialMessage={`"${ad.title}" (İlan No: ${ad.id}) ilanınızla ilgili yazdığınız teklif hakkında iletişime geçiyorum.`}
                                                />
                                            </div>
                                        )}
                                        {bid.status === 'ACCEPTED' && (
                                            <span className="badge badge-active" style={{ fontSize: '0.7rem' }}>Kabul Edildi</span>
                                        )}
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
}
