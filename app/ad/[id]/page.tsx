import { prisma } from "@/lib/prisma";
import { auth } from "@/auth";
import { notFound } from "next/navigation";
import Link from "next/link";
import BidForm from "./BidForm";
import ImageSlider from "./ImageSlider";
import { AdActions } from "./AdActions";
import { FavoriteButton } from "@/components/FavoriteButton";

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

    // Increment view count silently (fire & forget)
    prisma.ad.update({ where: { id }, data: { views: { increment: 1 } } }).catch(() => { });

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
                include: {
                    user: { select: { id: true, name: true } },
                },
            },
        },
    });

    if (!ad) notFound();

    const adData = ad as any;
    const highestBid = adData.bids[0];
    const isOwner = session?.user?.id === adData.userId;

    let displayPhone: string | null = null;
    let displayName = ad.user.name;

    if (!session?.user) {
        displayName = "Gizli Kullanıcı";
        displayPhone = null;
        ad.bids.forEach((bid: any) => {
            bid.user.name = "Gizli Kullanıcı";
        });
    } else if (!isOwner) {
        const nameParts = ad.user.name.trim().split(" ");
        if (nameParts.length > 1) {
            const firstName = nameParts.slice(0, -1).join(" ");
            const lastName = nameParts[nameParts.length - 1];
            displayName = `${firstName} ${lastName.charAt(0)}.`;
        } else if (nameParts.length === 1 && nameParts[0].length > 1) {
            displayName = `${nameParts[0].charAt(0)}.`;
        }

        if (ad.showPhone) {
            displayPhone = ad.user.phone;
        } else {
            displayPhone = null;
        }

        // Mask bidders
        ad.bids.forEach((bid: any) => {
            if (session?.user?.id !== bid.user.id) {
                const parts = bid.user.name.trim().split(" ");
                if (parts.length > 1) {
                    const firstName = parts.slice(0, -1).join(" ");
                    const lastName = parts[parts.length - 1];
                    bid.user.name = `${firstName} ${lastName.charAt(0)}.`;
                } else if (parts.length === 1 && parts[0].length > 1) {
                    bid.user.name = `${parts[0].charAt(0)}.`;
                }
            }
        });
    } else {
        displayPhone = ad.user.phone;
    }

    // Check if favorited by the current user
    let isFavorited = false;
    if (session?.user?.id) {
        const fav = await prisma.favorite.findUnique({
            where: {
                userId_adId: {
                    userId: session.user.id,
                    adId: ad.id,
                },
            },
        });
        isFavorited = !!fav;
    }

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

                            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "0.75rem" }}>
                                <h1 style={{ fontSize: "1.5rem", fontWeight: 700 }}>{ad.title}</h1>
                                <FavoriteButton
                                    adId={ad.id}
                                    initialIsFavorite={isFavorited}
                                    isLoggedIn={!!session?.user}
                                />
                            </div>

                            <div style={{ display: "flex", gap: "1rem", marginBottom: "1.25rem", color: "var(--text-secondary)", fontSize: "0.9rem" }}>
                                <span>📍 {ad.province.name}, {ad.district.name}</span>
                                <span>👤 {displayName}</span>
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
                                    {displayPhone && (
                                        <a
                                            href={`tel:${displayPhone}`}
                                            className="btn btn-secondary btn-full"
                                        >
                                            📞 {displayPhone} - Satıcıyı Ara
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
                            {!isOwner && !session?.user && displayPhone && (
                                <div style={{ marginTop: "1.25rem" }}>
                                    <a
                                        href={`tel:${displayPhone}`}
                                        className="btn btn-secondary btn-full"
                                    >
                                        📞 {displayPhone} - Satıcıyı Ara
                                    </a>
                                </div>
                            )}
                        </div>
                    </div>
                </div>

                {/* Sağ: Açık Artırma veya Sabit Fiyat */}
                <div>
                    {adData.isFixedPrice ? (
                        <div className="auction-card">
                            <div style={{ marginBottom: "1.25rem" }}>
                                <div className="auction-label" style={{ color: "var(--primary)" }}>
                                    Sabit Fiyatlı Ürün
                                </div>
                                <div style={{ fontSize: "1.75rem", fontWeight: 700, color: "var(--text-secondary)", marginTop: "0.5rem" }}>
                                    {formatPrice(ad.price)}
                                </div>
                            </div>
                            <div style={{ display: "flex", gap: "0.5rem", marginBottom: "1.25rem" }}>
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

                            {/* Satın Alma / İletişime Geçme */}
                            {!isOwner && session?.user ? (
                                <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                                    <AdActions
                                        actionType="MESSAGE"
                                        adId={ad.id}
                                        sellerId={ad.userId}
                                        currentUser={session.user}
                                        customLabel="⚡ Hemen Satın Al"
                                        initialMessage={`Merhaba, "${ad.title}" (İlan No: ${ad.id}) ilanınızı ${formatPrice(ad.price)} fiyatından satın almak istiyorum.`}
                                    />
                                    <div style={{ fontSize: "0.8125rem", color: "var(--text-muted)", textAlign: "center" }}>
                                        Satıcıyla anlaşıp güvenli ödeme/kargo koşullarını belirleyebilirsiniz.
                                    </div>
                                </div>
                            ) : !session?.user ? (
                                <div style={{ textAlign: "center", padding: "1.5rem 0", border: "1px dashed var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg-card-hover)" }}>
                                    <p className="text-muted text-sm" style={{ marginBottom: "0.75rem" }}>
                                        Satıcıyla iletişime geçmek için giriş yapmalısınız.
                                    </p>
                                    <Link href="/login" className="btn btn-primary btn-full">
                                        Giriş Yap
                                    </Link>
                                </div>
                            ) : (
                                <div style={{ textAlign: "center", padding: "1.25rem", background: "var(--primary-50)", borderRadius: "var(--radius-md)", color: "var(--primary-dark)", border: "1px solid var(--primary-100)" }}>
                                    <strong style={{ display: "block", marginBottom: "0.25rem" }}>Bu ilan size ait</strong>
                                    Sabit fiyatlı ürününüz yayında. Müşterilerden mesaj bekleyin.
                                </div>
                            )}
                        </div>
                    ) : (
                        <div className="auction-card">
                            <div style={{ marginBottom: "1.25rem" }}>
                                <div className="auction-label">
                                    {highestBid ? "Güncel Fiyat (En Yüksek Teklif)" : (ad.startingBid === null ? "Açılış (Serbest Teklif)" : "Minimum Açılış Teklifi")}
                                </div>
                                <div style={{ fontSize: "1.25rem", fontWeight: 600, color: "var(--text-secondary)" }}>
                                    {highestBid ? formatPrice(highestBid.amount) : (ad.startingBid === null ? formatPrice(1) : formatPrice(ad.startingBid))}
                                </div>
                                <div className="text-muted" style={{ fontSize: "0.875rem", marginTop: "0.25rem", display: "flex", justifyContent: "space-between" }}>
                                    <span>Piyasa Değeri: <span style={{ textDecoration: "line-through" }}>{formatPrice(ad.price)}</span></span>
                                    <span style={{ color: "var(--primary)", fontWeight: 500 }}>➕ Pey Aralığı: {formatPrice(ad.minBidStep)}</span>
                                </div>
                                {highestBid && (
                                    <div className="text-muted text-sm" style={{ marginTop: "0.25rem" }}>
                                        Son teklif: {highestBid.user.name} tarafından verildi
                                    </div>
                                )}
                            </div>

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

                            {/* Hemen Al (Buy It Now) */}
                            {ad.buyItNowPrice !== null && (
                                <div style={{ marginBottom: "1.25rem", padding: "1rem", background: "var(--bg-secondary)", borderRadius: "var(--radius-md)", border: "1px dashed var(--primary)", display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                        <div style={{ fontWeight: 600, color: "var(--text-secondary)" }}>Hemen Al Fiyatı</div>
                                        <div style={{ fontSize: "1.25rem", fontWeight: 700, color: "var(--primary)" }}>{formatPrice(ad.buyItNowPrice)}</div>
                                    </div>
                                    <div style={{ fontSize: "0.8125rem", color: "var(--text-muted)" }}>
                                        Açık artırmanın bitmesini beklemeden bu ürünü hemen satın alabilirsiniz.
                                    </div>
                                    {!isOwner && session?.user ? (
                                        <AdActions
                                            actionType="MESSAGE"
                                            adId={ad.id}
                                            sellerId={ad.userId}
                                            currentUser={session.user}
                                            customLabel="⚡ Hemen Satın Al"
                                            initialMessage={`Merhaba, "${ad.title}" (İlan No: ${ad.id}) ilanınızı Hemen Al fiyatı olan ${formatPrice(ad.buyItNowPrice)} üzerinden satın almak istiyorum.`}
                                        />
                                    ) : !session?.user && (
                                        <Link href="/login" className="btn btn-primary btn-full">
                                            Hemen Almak İçin Giriş Yap
                                        </Link>
                                    )}
                                </div>
                            )}

                            {/* Teklif Formu */}
                            {!isOwner && session?.user ? (
                                <BidForm
                                    adId={ad.id}
                                    currentHighest={highestBid?.amount ?? (ad.startingBid !== null ? ad.startingBid : 0)}
                                    minStep={ad.bids.length > 0 ? ad.minBidStep : (ad.startingBid === null ? 1 : 0)}
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
                                    {ad.bids.map((bid: any, i: number) => (
                                        <div key={bid.id} className="bid-item" style={{ display: 'flex', flexDirection: 'column', gap: '8px', padding: '12px', background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: 'var(--radius-md)', marginBottom: '8px' }}>
                                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                                <div>
                                                    <span className="bid-item-user" style={{ fontWeight: 600 }}>
                                                        {i === 0 && "🏆 "}
                                                        {bid.user.name}
                                                    </span>
                                                    <span className="bid-item-amount" style={{ marginLeft: '8px', color: 'var(--primary)', fontWeight: 700 }}>{formatPrice(bid.amount)}</span>
                                                </div>
                                                {bid.status === 'ACCEPTED' && (
                                                    <span className="badge badge-active" style={{ fontSize: '0.7rem' }}>Kabul Edildi</span>
                                                )}
                                                {bid.status === 'REJECTED' && (
                                                    <span className="badge" style={{ fontSize: '0.7rem', background: 'rgba(239,68,68,0.1)', color: '#ef4444' }}>Reddedildi</span>
                                                )}
                                            </div>
                                            {isOwner && (
                                                <div style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap', marginTop: '4px' }}>
                                                    {bid.status === 'PENDING' && (
                                                        <>
                                                            <AdActions actionType="ACCEPT_BID" bidId={bid.id} currentUser={session?.user} />
                                                            <AdActions actionType="CANCEL_BID" bidId={bid.id} currentUser={session?.user} />
                                                        </>
                                                    )}
                                                    {bid.status === 'ACCEPTED' && (
                                                        <AdActions actionType="CANCEL_BID" bidId={bid.id} currentUser={session?.user} />
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
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
