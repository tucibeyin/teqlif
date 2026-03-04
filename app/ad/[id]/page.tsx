import { prisma } from "@/lib/prisma";
export const revalidate = 0;
import { auth } from "@/auth";
import { notFound } from "next/navigation";
import Link from "next/link";
import BidForm from "./BidForm";
import ImageSlider from "./ImageSlider";
import { AdActions } from "./AdActions";
import { FavoriteButton } from "@/components/FavoriteButton";
import { findPath, categoryTree } from "@/lib/categories";
import LiveArenaWrapper from "./LiveArenaWrapper";
import StartBroadcastButton from "./StartBroadcastButton";

function formatPrice(price: number) {
    return new Intl.NumberFormat("tr-TR", {
        style: "currency",
        currency: "TRY",
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
    }).format(price);
}

function formatDate(date: Date) {
    return new Intl.DateTimeFormat("tr-TR", {
        day: "numeric",
        month: "long",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
    }).format(new Date(date));
}

function formatNameInitials(name: string) {
    if (!name) return "A.";
    const parts = name.trim().split(/\s+/);
    if (parts.length === 1) return `${parts[0].charAt(0).toUpperCase()}.`;
    return parts
        .map(p => `${p.charAt(0).toUpperCase()}.`)
        .join("");
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
                where: { status: { in: ['PENDING', 'ACCEPTED'] } },
                orderBy: [{ amount: "desc" }, { createdAt: "desc" }],
                take: 50,
                include: {
                    user: { select: { id: true, name: true, phone: true } },
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

    } else {
        displayPhone = ad.user.phone;
    }

    // Mask bidders (everyone sees masked bidders except the bidder themselves)
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

            <div className="ad-detail" style={adData.isLive ? { paddingTop: "0.5rem", marginTop: "-1rem" } : {}}>
                {/* Sol: Görsel ve Detay */}
                <div>
                    <div className="ad-detail-images">
                        {adData.isLive ? (
                            <div className="card" style={{ overflow: "hidden", border: "2px solid #ef4444", borderRadius: "1.5rem" }}>
                                <div style={{ background: "#ef4444", color: "white", padding: "0.5rem 1rem", fontWeight: "bold", display: "flex", alignItems: "center", gap: "0.5rem" }}>
                                    <span style={{ display: "inline-block", width: "8px", height: "8px", borderRadius: "50%", background: "white", animation: "pulse 1.5s infinite" }}></span>
                                    {!adData.isLive && isOwner ? "YAYIN HAZIRLIK ODASI (Sadece Siz Görüyorsunuz)" : "CANLI AÇIK ARTTIRMA ARENASI"}
                                </div>
                                <LiveArenaWrapper
                                    roomId={adData.id}
                                    adId={adData.id}
                                    sellerId={ad.userId}
                                    isOwner={isOwner}
                                    buyItNowPrice={ad.buyItNowPrice}
                                    startingBid={ad.startingBid}
                                    minBidStep={ad.minBidStep}
                                    initialHighestBid={highestBid?.amount ?? 0}
                                    initialIsAuctionActive={adData.isAuctionActive}
                                    adOwnerName={displayName}
                                />
                            </div>
                        ) : (
                            ad.images && ad.images.length > 0 ? (
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
                            )
                        )}
                    </div>

                    {/* İlan Detayları */}
                    <div className="card" style={{ marginTop: adData.isLive ? "1rem" : "1.5rem" }}>
                        <div className="card-body">
                            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "1rem" }}>
                                <div>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px', flexWrap: 'wrap' }}>
                                        {(() => {
                                            const path = findPath(ad.category.slug, categoryTree);
                                            if (path && path.length > 1) {
                                                return path.map((node, i) => (
                                                    <span key={node.slug} style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                                                        {i > 0 && <span style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>›</span>}
                                                        <span className="ad-card-badge" style={{ fontSize: '0.75rem', padding: '2px 8px' }}>
                                                            {node.icon ? `${node.icon} ` : ''}{node.name}
                                                        </span>
                                                    </span>
                                                ));
                                            }
                                            return <span className="ad-card-badge">{ad.category.icon} {ad.category.name}</span>;
                                        })()}
                                    </div>
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

                            <div style={{ display: "flex", gap: "1rem", marginBottom: "1.25rem", color: "var(--text-secondary)", fontSize: "0.9rem", flexWrap: "wrap" }}>
                                <span>📍 {ad.province.name}, {ad.district.name}</span>
                                <span>👤 {displayName}</span>
                                {ad.expiresAt && (
                                    <span style={{ color: "var(--primary)" }}>⏰ Bitiş: {formatDate(ad.expiresAt)}</span>
                                )}
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

                        </div>
                    </div>
                </div>

                {/* Sağ: Açık Arttırma veya Sabit Fiyat */}
                <div>
                    {/* Satıcı İletişim Kartı */}
                    <div className="card" style={{ marginBottom: "1.5rem" }}>
                        <div className="card-body">
                            <div style={{ display: "flex", alignItems: "center", gap: "1rem", marginBottom: "1.25rem" }}>
                                <div style={{
                                    width: "48px",
                                    height: "48px",
                                    borderRadius: "50%",
                                    background: "var(--primary-50)",
                                    color: "var(--primary)",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    fontSize: "1.25rem",
                                    fontWeight: 700
                                }}>
                                    {displayName.charAt(0)}
                                </div>
                                <div style={{ flex: 1 }}>
                                    <div style={{ fontWeight: 600, fontSize: "1.1rem" }}>{displayName}</div>
                                    <div style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>İlan Sahibi</div>
                                </div>
                            </div>

                            {!isOwner ? (
                                session?.user ? (
                                    <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                                        {displayPhone && (
                                            <a
                                                href={`tel:${displayPhone}`}
                                                style={{
                                                    display: "flex",
                                                    justifyContent: "center",
                                                    alignItems: "center",
                                                    gap: "0.5rem",
                                                    background: "linear-gradient(135deg, rgb(0, 180, 204), rgb(0, 141, 161))",
                                                    color: "white",
                                                    padding: "0.75rem 1.25rem",
                                                    borderRadius: "var(--radius-md)",
                                                    fontWeight: "bold",
                                                    textDecoration: "none",
                                                    boxShadow: "rgba(0, 180, 204, 0.3) 0px 4px 12px"
                                                }}
                                            >
                                                📞 {displayPhone} - İlan Sahibini Ara
                                            </a>
                                        )}
                                        <AdActions
                                            actionType="MESSAGE"
                                            adId={ad.id}
                                            sellerId={ad.userId}
                                            currentUser={session.user}
                                            customLabel="💬 İlan Sahibine Mesaj Gönder"
                                            initialMessage={`"${ad.title}" (İlan No: ${ad.id}) ilanı hakkında bilgi almak istiyorum.`}
                                        />
                                    </div>
                                ) : (
                                    <div style={{ textAlign: "center", padding: "1rem", border: "1px dashed var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg-card-hover)" }}>
                                        <p className="text-muted text-sm" style={{ marginBottom: "0.75rem" }}>
                                            İlan sahibiyle iletişime geçmek için giriş yapmalısınız.
                                        </p>
                                        <Link href="/login" className="btn btn-primary btn-full">
                                            Giriş Yap
                                        </Link>
                                    </div>
                                )
                            ) : (
                                <div style={{ textAlign: "center", padding: "1rem", background: "var(--primary-50)", borderRadius: "var(--radius-md)", color: "var(--primary-dark)", border: "1px solid var(--primary-100)" }}>
                                    <strong style={{ display: "block", fontSize: "0.9rem" }}>Bu ilan size ait</strong>
                                </div>
                            )}
                            {isOwner && !adData.isLive && adData.status === 'ACTIVE' && (
                                <div style={{ marginTop: "1rem", paddingTop: "1rem", borderTop: "1px solid var(--border)" }}>
                                    <div style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginBottom: "0.5rem", textAlign: "center" }}>
                                        Canlı olarak ürününüzü tanıtıp, anlık teqlifler alabilirsiniz.
                                    </div>
                                    <StartBroadcastButton adId={ad.id} />
                                </div>
                            )}
                        </div>
                    </div>
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

                            {/* Satın Alma Bilgisi */}
                            {isOwner && (
                                <div style={{ textAlign: "center", padding: "1.25rem", background: "var(--primary-50)", borderRadius: "var(--radius-md)", color: "var(--primary-dark)", border: "1px solid var(--primary-100)" }}>
                                    Sabit fiyatlı ürününüz yayında.
                                </div>
                            )}
                        </div>
                    ) : (
                        <div style={{
                            background: "rgba(255, 255, 255, 0.7)",
                            backdropFilter: "blur(20px)",
                            WebkitBackdropFilter: "blur(20px)",
                            border: "1px solid rgba(0, 180, 204, 0.2)",
                            borderRadius: "1.5rem",
                            padding: "1.5rem",
                            position: "sticky",
                            top: "80px",
                            boxShadow: "rgba(0, 180, 204, 0.1) 0px 20px 40px",
                            color: "var(--text-primary)"
                        }}>
                            <div style={{ marginBottom: "1.25rem" }}>
                                <div style={{ fontSize: "0.85rem", opacity: 0.6, textTransform: "uppercase", letterSpacing: "1px", marginBottom: "4px" }}>
                                    {highestBid ? "GÜNCEL FİYAT" : (ad.startingBid === null ? "AÇILIŞ (SERBEST)" : "MİNİMUM AÇILIŞ")}
                                </div>
                                <div style={{ fontSize: "2rem", fontWeight: 900, color: "var(--primary)", textShadow: "rgba(0, 180, 204, 0.2) 0px 2px 10px" }}>
                                    {highestBid ? formatPrice(highestBid.amount) : (ad.startingBid === null ? formatPrice(1) : formatPrice(ad.startingBid))}
                                </div>
                                <div className="text-muted" style={{ fontSize: "0.875rem", marginTop: "0.5rem", display: "flex", justifyContent: "space-between", color: "var(--text-secondary)" }}>
                                    <span>Piyasa: <span style={{ textDecoration: "line-through" }}>{formatPrice(ad.price)}</span></span>
                                    <span style={{ color: "var(--primary)", fontWeight: 700 }}>➕ Aralık: {formatPrice(ad.minBidStep)}</span>
                                </div>
                                {highestBid && (
                                    <div style={{ fontSize: "0.85rem", marginTop: "0.5rem", color: "var(--text-secondary)" }}>
                                        Son teqlif: <span style={{ fontWeight: 700, color: "var(--text-primary)" }}>{highestBid.user.name}</span>
                                    </div>
                                )}
                            </div>

                            <div style={{ display: "flex", gap: "0.5rem", marginBottom: "1.25rem" }}>
                                <div style={{
                                    background: "rgba(0, 180, 204, 0.05)",
                                    border: "1px solid rgba(0, 180, 204, 0.1)",
                                    borderRadius: "12px",
                                    padding: "0.5rem",
                                    flex: 1,
                                    textAlign: "center",
                                }}>
                                    <div style={{ fontWeight: 800, color: "var(--primary)", fontSize: "1.1rem" }}>{ad.bids.length}</div>
                                    <div style={{ fontSize: "0.7rem", opacity: 0.6, textTransform: "uppercase" }}>Teqlif</div>
                                </div>
                                <div style={{
                                    background: "rgba(0, 180, 204, 0.05)",
                                    border: "1px solid rgba(0, 180, 204, 0.1)",
                                    borderRadius: "12px",
                                    padding: "0.5rem",
                                    flex: 1,
                                    textAlign: "center",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center"
                                }}>
                                    <span style={{
                                        padding: "4px 12px",
                                        borderRadius: "20px",
                                        background: ad.status === "ACTIVE" ? "rgba(34, 197, 94, 0.1)" : "rgba(0,0,0,0.05)",
                                        color: ad.status === "ACTIVE" ? "#16a34a" : "var(--text-secondary)",
                                        fontSize: "0.75rem",
                                        fontWeight: 800
                                    }}>
                                        {ad.status === "ACTIVE" ? "AKTİF" : ad.status === "SOLD" ? "SATILDI" : "SÜRESİ DOLDU"}
                                    </span>
                                </div>
                            </div>

                            {/* Hemen Al (Buy It Now) */}
                            {ad.status === 'ACTIVE' && ad.buyItNowPrice !== null && !adData.isLive && (
                                <div style={{ marginBottom: "1.25rem", padding: "1rem", background: "rgba(255, 255, 255, 0.05)", borderRadius: "1rem", border: "1px dashed rgba(0, 180, 204, 0.4)", display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                        <div style={{ fontWeight: 600, opacity: 0.8 }}>Hemen Al Fiyatı</div>
                                        <div style={{ fontSize: "1.25rem", fontWeight: 800, color: "var(--primary)" }}>{formatPrice(ad.buyItNowPrice)}</div>
                                    </div>
                                    <div style={{ fontSize: "0.75rem", opacity: 0.6 }}>
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
                                        <Link href="/login" style={{
                                            background: "rgba(255,255,255,0.1)",
                                            color: "white",
                                            padding: "0.75rem",
                                            borderRadius: "0.75rem",
                                            textAlign: "center",
                                            textDecoration: "none",
                                            fontWeight: 700,
                                            fontSize: "0.9rem"
                                        }}>
                                            Hemen Almak İçin Giriş Yap
                                        </Link>
                                    )}
                                </div>
                            )}

                            {/* Teqlif Formu & Mesaj Butonu */}
                            <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                                {ad.status === 'ACTIVE' && !isOwner && session?.user && !adData.isLive && (
                                    <BidForm
                                        adId={ad.id}
                                        currentHighest={highestBid?.amount ?? 0}
                                        minStep={highestBid ? ad.minBidStep : Math.max(ad.startingBid ?? 0, ad.minBidStep)}
                                    />
                                )}

                                {!session?.user && !adData.isLive && (
                                    <div style={{ textAlign: "center", padding: "1.5rem", background: "rgba(255, 255, 255, 0.05)", borderRadius: "1rem", border: "1px dashed rgba(255, 255, 255, 0.2)" }}>
                                        <p style={{ fontSize: "0.85rem", opacity: 0.7, marginBottom: "1rem" }}>
                                            Bu ilana teqlif vermek için giriş yapmalısınız.
                                        </p>
                                        <Link href="/login" style={{
                                            display: "block",
                                            background: "linear-gradient(135deg, rgb(0, 180, 204), rgb(0, 141, 161))",
                                            color: "white",
                                            padding: "0.75rem",
                                            borderRadius: "0.75rem",
                                            fontWeight: 800,
                                            textDecoration: "none"
                                        }}>
                                            Giriş Yap
                                        </Link>
                                    </div>
                                )}

                                {isOwner && (
                                    <div style={{ textAlign: "center", padding: "1.25rem", background: "rgba(0, 180, 204, 0.1)", borderRadius: "1rem", border: "1px solid rgba(0, 180, 204, 0.2)" }}>
                                        <strong style={{ display: "block", marginBottom: "0.25rem", color: "var(--primary)" }}>Bu ilan size ait</strong>
                                        <span style={{ fontSize: "0.85rem", opacity: 0.8 }}>
                                            {ad.status === 'ACTIVE' ? "Kendi ilanınıza teqlif veremezsiniz." : "İlan satış işlemi tamamlandı."}
                                        </span>
                                    </div>
                                )}
                            </div>

                            {/* Teqlif Geçmişi */}
                            {ad.bids.length > 0 && (
                                <div className="bid-history" style={{ marginTop: "1.5rem" }}>
                                    <div style={{ fontWeight: 600, fontSize: "0.875rem", marginBottom: "0.5rem" }}>
                                        Teqlif Geçmişi ({ad.bids.length})
                                    </div>
                                    <div style={{ maxHeight: "350px", overflowY: "auto", paddingRight: "0.5rem" }}>
                                        {ad.bids.map((bid: any, i: number) => (
                                            <div key={bid.id} className="bid-item" style={{
                                                display: 'flex',
                                                flexDirection: 'column',
                                                padding: '12px 16px',
                                                background: 'rgba(255,255,255,0.6)',
                                                border: '1px solid rgba(0, 180, 204, 0.1)',
                                                borderRadius: '12px',
                                                marginBottom: '10px',
                                                transition: 'all 0.2s ease',
                                                boxShadow: '0 2px 4px rgba(0, 180, 204, 0.05)'
                                            }}>
                                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                                    <div style={{ flex: 1 }}>
                                                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                                                            <span className="bid-item-user" style={{ fontWeight: 700, color: 'var(--text-primary)' }}>
                                                                {i === 0 && "🏆 "}
                                                                {formatNameInitials(bid.user.name)}
                                                            </span>
                                                            <span style={{ color: 'var(--primary)', fontWeight: 800, fontSize: '1rem' }}>
                                                                {formatPrice(bid.amount)}
                                                            </span>
                                                        </div>
                                                        <div style={{ fontSize: '0.75rem', marginTop: '4px', display: 'flex', alignItems: 'center', gap: '6px', color: 'var(--text-secondary)' }}>
                                                            <span>{timeAgo(bid.createdAt)}</span>
                                                            {bid.status === 'ACCEPTED' && (
                                                                <span style={{
                                                                    padding: '2px 8px',
                                                                    borderRadius: '20px',
                                                                    fontSize: '0.65rem',
                                                                    background: 'rgba(34,197,94,0.1)',
                                                                    color: '#22c55e',
                                                                    fontWeight: 600,
                                                                    textTransform: 'uppercase'
                                                                }}>Kabul Edildi</span>
                                                            )}
                                                            {bid.status === 'REJECTED' && (
                                                                <span style={{
                                                                    padding: '2px 8px',
                                                                    borderRadius: '20px',
                                                                    fontSize: '0.65rem',
                                                                    background: 'rgba(239,68,68,0.1)',
                                                                    color: '#ef4444',
                                                                    fontWeight: 600,
                                                                    textTransform: 'uppercase'
                                                                }}>Reddedildi</span>
                                                            )}
                                                        </div>
                                                    </div>
                                                </div>

                                                {(isOwner || (session?.user?.id === bid.userId) || ad.status !== 'SOLD' && (bid.status === 'PENDING' || bid.status === 'ACCEPTED')) && (
                                                    <div style={{
                                                        display: 'flex',
                                                        gap: '8px',
                                                        alignItems: 'center',
                                                        marginTop: '12px',
                                                        paddingTop: '12px',
                                                        borderTop: '1px dashed rgba(0, 180, 204, 0.1)',
                                                        flexWrap: 'wrap'
                                                    }}>
                                                        {isOwner && ad.status !== 'SOLD' && bid.status === 'ACCEPTED' && (
                                                            <AdActions actionType="FINALIZE_SALE" bidId={bid.id} currentUser={session?.user} />
                                                        )}

                                                        {isOwner && bid.status === 'ACCEPTED' && bid.user.phone && (
                                                            <a
                                                                href={`tel:${bid.user.phone}`}
                                                                style={{
                                                                    display: 'flex',
                                                                    alignItems: 'center',
                                                                    justifyContent: 'center',
                                                                    padding: '6px 12px',
                                                                    fontSize: '0.8rem',
                                                                    fontWeight: 600,
                                                                    gap: '6px',
                                                                    borderRadius: '6px',
                                                                    background: 'rgba(0, 180, 204, 0.05)',
                                                                    color: 'var(--primary)',
                                                                    border: '1px solid rgba(0, 180, 204, 0.2)'
                                                                }}
                                                            >
                                                                📞 Ara
                                                            </a>
                                                        )}

                                                        {(isOwner || (session?.user?.id === bid.userId)) && (
                                                            <AdActions
                                                                actionType="MESSAGE"
                                                                adId={ad.id}
                                                                sellerId={isOwner ? bid.userId : ad.userId}
                                                                currentUser={session?.user}
                                                                isMessageBidder={true}
                                                                initialMessage={isOwner
                                                                    ? `"${ad.title}" (İlan No: ${ad.id}) ilanınızla ilgili yazdığınız teqlif hakkında iletişime geçiyorum.`
                                                                    : `"${ad.title}" (İlan No: ${ad.id}) ilanına verdiğim teqlif hakkında iletişime geçmek istiyorum.`
                                                                }
                                                            />
                                                        )}

                                                        {isOwner && ad.status !== 'SOLD' && bid.status === 'PENDING' && (
                                                            <AdActions actionType="ACCEPT_BID" bidId={bid.id} currentUser={session?.user} />
                                                        )}

                                                        {isOwner && ad.status !== 'SOLD' && (bid.status === 'PENDING' || bid.status === 'ACCEPTED') && (
                                                            <AdActions actionType="CANCEL_BID" bidId={bid.id} currentUser={session?.user} />
                                                        )}
                                                    </div>
                                                )}
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            )}
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
