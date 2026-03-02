import Link from "next/link";
import Image from "next/image";
import { prisma } from "@/lib/prisma";
import { categoryTree, findPath } from "@/lib/categories";
import type { CategoryNode } from "@/lib/categories";
import { cache } from "react";

export const dynamic = "force-dynamic";

/** Sidebar kategori node'unu render eder: çocuğu varsa accordion, yoksa link */
function renderSidebarNode(
  node: CategoryNode,
  activeCategory: string | undefined,
  activePathSlugs: Set<string>,
  depth = 0
): React.ReactNode {
  const isActive = activeCategory === node.slug;
  const isPathToActive = activePathSlugs.has(node.slug);

  if (node.children.length === 0) {
    // Yaprak → link
    return (
      <Link
        key={node.slug}
        href={`/?category=${node.slug}`}
        style={{
          display: "flex", alignItems: "center", gap: "0.625rem",
          padding: depth === 0 ? "0.5rem 0.75rem" : "0.375rem 0.625rem",
          paddingLeft: depth > 0 ? `${0.75 + depth * 0.75}rem` : undefined,
          borderRadius: "var(--radius-md)", textDecoration: "none",
          fontWeight: isActive ? 700 : 500,
          color: isActive ? "var(--primary)" : "var(--text-secondary)",
          background: isActive ? "rgba(0,188,212,0.08)" : "transparent",
          fontSize: depth === 0 ? "0.9rem" : "0.84rem",
          transition: "all 0.15s", marginBottom: "1px",
        }}
      >
        {node.icon && <span>{node.icon}</span>} {node.name}
      </Link>
    );
  }

  // İç node → accordion
  return (
    <details
      key={node.slug}
      open={isPathToActive || isActive || undefined}
      style={{ marginBottom: "1px" }}
    >
      <summary style={{
        display: "flex", alignItems: "center", gap: "0.625rem",
        padding: depth === 0 ? "0.5rem 0.75rem" : "0.375rem 0.625rem",
        paddingLeft: depth > 0 ? `${0.75 + depth * 0.75}rem` : undefined,
        borderRadius: "var(--radius-md)", cursor: "pointer",
        fontWeight: isActive ? 700 : 500,
        color: isActive ? "var(--primary)" : "var(--text-secondary)",
        background: isActive ? "rgba(0,188,212,0.08)" : "transparent",
        fontSize: depth === 0 ? "0.9rem" : "0.84rem",
        listStyle: "none", userSelect: "none",
      }}>
        {node.icon && <span>{node.icon}</span>} {node.name}
        <span style={{ marginLeft: "auto", fontSize: "0.7rem", color: "var(--text-muted)" }}>▾</span>
      </summary>
      <div>
        {node.children.map((child) =>
          renderSidebarNode(child, activeCategory, activePathSlugs, depth + 1)
        )}
      </div>
    </details>
  );
}

const getAds = cache(async (categorySlug?: string, limit = 24) => {
  try {
    const where: Record<string, any> = {
      status: "ACTIVE",
      OR: [
        { expiresAt: null },
        { expiresAt: { gt: new Date() } },
      ],
    };
    if (categorySlug) where.category = { slug: categorySlug };

    return await prisma.ad.findMany({
      where,
      take: limit,
      orderBy: { createdAt: "desc" },
      include: {
        user: { select: { name: true } },
        category: true,
        province: true,
        district: true,
        _count: { select: { bids: true } },
        bids: {
          where: { status: { in: ['PENDING', 'ACCEPTED'] } },
          orderBy: { amount: "desc" },
          take: 1,
          select: { amount: true }
        },
      },
    });
  } catch {
    return [];
  }
});

const getLiveAuctions = cache(async () => {
  try {
    return await prisma.ad.findMany({
      where: {
        status: "ACTIVE",
        isLive: true,
        isAuction: true,
      },
      take: 10,
      orderBy: { auctionStartTime: "desc" },
      include: {
        user: { select: { name: true, avatar: true } },
        category: true,
        province: true,
        _count: { select: { bids: true } },
        bids: {
          where: { status: { in: ['PENDING', 'ACCEPTED'] } },
          orderBy: { amount: "desc" },
          take: 1,
          select: { amount: true }
        },
      },
    });
  } catch {
    return [];
  }
});

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
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);
  if (minutes < 60) return `${minutes} dk`;
  if (hours < 24) return `${hours} sa`;
  return `${days} gün`;
}

function daysLeft(expiresAt: Date | null) {
  if (!expiresAt) return null;
  const diff = new Date(expiresAt).getTime() - Date.now();
  const days = Math.ceil(diff / 86400000);
  if (days <= 0) return null;
  return days;
}

export default async function HomePage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string; tab?: string }>;
}) {
  const params = await searchParams;
  const activeCategory = params.category;
  const activeTab = params.tab || "all"; // 'all' veya 'live'

  // Calculate path once O(N)
  const path = activeCategory ? findPath(activeCategory, categoryTree) : null;
  const activePathSlugs = new Set(path?.map(n => n.slug) || []);

  const allAds = await getAds(activeCategory, 24);
  const liveAuctions = await getLiveAuctions();

  // Filter based on tab
  let displayAds = allAds;
  if (activeTab === "live") {
    displayAds = allAds.filter(a => a.isAuction);
  } else {
    displayAds = allAds.filter(a => !a.isAuction || (a.isAuction && !a.isLive)); // Canlı olanlar tepede story'de
  }

  const latestAds = activeCategory ? [] : displayAds.slice(0, 8);
  const featuredAds = activeCategory ? displayAds : displayAds.slice(0, 16);

  return (
    <>
      <section className="hero">
        <div className="container">
          <h1 className="hero-title">
            Türkiye&apos;nin En Büyük<br />
            <span style={{ color: "var(--primary)" }}>İlan Platformu</span>
          </h1>
          <p className="hero-subtitle">
            Kategori ve konum seçerek saniyeler içinde ilan ver. Açık artırmaya katıl, en iyi teklifleri ver.
          </p>
          <div className="hero-actions">
            <Link href="/post-ad" className="btn btn-primary btn-lg">
              🚀 Ücretsiz İlan Ver
            </Link>
            <Link href="#ilanlar" className="btn btn-secondary btn-lg">
              İlanları Gör
            </Link>
          </div>
        </div>
      </section>

      {/* CANLI YAYIN VİTRİNİ (STORIES) */}
      {!activeCategory && liveAuctions.length > 0 && (
        <div className="container" style={{ paddingTop: "2rem", paddingBottom: "1rem" }}>
          <div className="section-header" style={{ marginBottom: "1rem" }}>
            <h2 className="section-title" style={{ fontSize: "1.25rem", display: "flex", alignItems: "center", gap: "0.5rem" }}>
              <span style={{ display: "inline-block", width: "10px", height: "10px", borderRadius: "50%", background: "#ef4444", animation: "pulse 2s infinite" }}></span>
              🔥 Şu An Canlı
            </h2>
          </div>
          <div style={{
            display: "flex", gap: "1rem", overflowX: "auto", paddingBottom: "1rem", scrollBehavior: "smooth",
            scrollSnapType: "x mandatory", WebkitOverflowScrolling: "touch", margin: "0 -1rem", padding: "0 1rem"
          }}>
            {liveAuctions.map((auction) => (
              <Link key={auction.id} href={`/ad/${auction.id}`} style={{ textDecoration: "none", flexShrink: 0, width: "160px", scrollSnapAlign: "start" }}>
                <div style={{
                  position: "relative", width: "160px", height: "240px", borderRadius: "var(--radius-lg)", overflow: "hidden",
                  boxShadow: "var(--shadow-md)", border: "2px solid #ef4444", background: "var(--bg-secondary)"
                }}>
                  {auction.images && auction.images.length > 0 ? (
                    <Image src={auction.images[0]} alt={auction.title} fill style={{ objectFit: "cover" }} />
                  ) : (
                    <div style={{ position: "absolute", top: 0, left: 0, width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "3rem" }}>
                      {auction.category.icon}
                    </div>
                  )}
                  {/* Karanlık gradyan */}
                  <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, height: "60%", background: "linear-gradient(to top, rgba(0,0,0,0.9) 0%, transparent 100%)" }}></div>

                  {/* Canlı Badge */}
                  <div style={{ position: "absolute", top: "8px", left: "8px", background: "#ef4444", color: "white", fontSize: "0.7rem", fontWeight: "bold", padding: "2px 6px", borderRadius: "100px", display: "flex", alignItems: "center", gap: "4px" }}>
                    <span style={{ width: "6px", height: "6px", borderRadius: "50%", background: "white", animation: "pulse 1.5s infinite" }}></span> CANLI
                  </div>

                  {/* Kategori Müşteri */}
                  <div style={{ position: "absolute", bottom: "8px", left: "8px", right: "8px", color: "white" }}>
                    <div style={{ fontSize: "0.85rem", fontWeight: 700, display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden", lineHeight: 1.2, marginBottom: "4px", textShadow: "0 1px 2px rgba(0,0,0,0.5)" }}>
                      {auction.title}
                    </div>
                    <div style={{ fontSize: "0.75rem", color: "rgba(255,255,255,0.8)", display: "flex", alignItems: "center", gap: "4px" }}>
                      👤 {auction.user.name.split(" ")[0]}
                    </div>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </div>
      )}

      <div className="container" id="ilanlar" style={{ paddingTop: "2rem" }}>
        <div style={{ display: "grid", gridTemplateColumns: "220px 1fr", gap: "2rem", alignItems: "start" }}>

          <aside style={{
            position: "sticky",
            top: "80px",
            background: "var(--bg-card)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-lg)",
            padding: "1rem",
            boxShadow: "var(--shadow-sm)"
          }}>
            <div style={{ fontWeight: 700, fontSize: "0.8rem", textTransform: "uppercase", letterSpacing: "0.05em", color: "var(--text-muted)", marginBottom: "0.75rem", padding: "0 0.5rem" }}>
              Kategoriler
            </div>
            <Link
              href="/"
              style={{
                display: "flex",
                alignItems: "center",
                gap: "0.625rem",
                padding: "0.5rem 0.75rem",
                borderRadius: "var(--radius-md)",
                textDecoration: "none",
                fontWeight: !activeCategory ? 700 : 500,
                color: !activeCategory ? "var(--primary)" : "var(--text-secondary)",
                background: !activeCategory ? "rgba(0,188,212,0.08)" : "transparent",
                fontSize: "0.9rem",
                transition: "all 0.15s",
                marginBottom: "2px",
              }}
            >
              <span>🏷️</span> Tümü
              <span style={{ marginLeft: "auto", fontSize: "0.75rem", color: "var(--text-muted)" }}>{allAds.length}</span>
            </Link>

            {categoryTree.map((node) => renderSidebarNode(node, activeCategory, activePathSlugs))}
          </aside>

          <div>
            <div className="section-header" style={{ marginBottom: "1rem", display: "flex", justifyContent: "space-between", alignItems: "flex-end", flexWrap: "wrap", gap: "1rem" }}>
              <div>
                <h2 className="section-title" style={{ fontSize: "1.25rem", marginBottom: "0.5rem" }}>
                  {activeCategory
                    ? (path ? path.map((n, i) => i === 0 ? `${n.icon ?? ""} ${n.name}`.trim() : n.name).join(" › ") + " İlanları" : "İlanlar")
                    : "Keşfet"}
                </h2>
                {/* TABS */}
                <div style={{ display: "flex", gap: "0.5rem", background: "var(--bg-secondary)", padding: "0.25rem", borderRadius: "100px", width: "fit-content" }}>
                  <Link href={`/?${new URLSearchParams({ ...Object.fromEntries(new URLSearchParams(params as any)), tab: "all" }).toString()}`} scroll={false} style={{
                    padding: "0.4rem 1rem", borderRadius: "100px", fontSize: "0.85rem", fontWeight: activeTab === "all" ? 600 : 500, textDecoration: "none",
                    background: activeTab === "all" ? "var(--bg-card)" : "transparent",
                    color: activeTab === "all" ? "var(--text-primary)" : "var(--text-muted)",
                    boxShadow: activeTab === "all" ? "0 1px 3px rgba(0,0,0,0.1)" : "none",
                    transition: "all 0.2s"
                  }}>
                    Hepsi
                  </Link>
                  <Link href={`/?${new URLSearchParams({ ...Object.fromEntries(new URLSearchParams(params as any)), tab: "live" }).toString()}`} scroll={false} style={{
                    padding: "0.4rem 1rem", borderRadius: "100px", fontSize: "0.85rem", fontWeight: activeTab === "live" ? 600 : 500, textDecoration: "none",
                    background: activeTab === "live" ? "var(--bg-card)" : "transparent",
                    color: activeTab === "live" ? "#ef4444" : "var(--text-muted)",
                    boxShadow: activeTab === "live" ? "0 1px 3px rgba(0,0,0,0.1)" : "none",
                    display: "flex", alignItems: "center", gap: "0.3rem", transition: "all 0.2s"
                  }}>
                    <span style={{ width: "6px", height: "6px", borderRadius: "50%", background: "#ef4444" }}></span> Mezatlar
                  </Link>
                </div>
              </div>
              <span className="text-sm text-muted" style={{ paddingBottom: "0.5rem" }}>{featuredAds.length} ilan</span>
            </div>

            {featuredAds.length === 0 ? (
              <div className="empty-state">
                <div className="empty-state-icon">📭</div>
                <div className="empty-state-title">Bu kategoride ilan yok</div>
                <p>Bu kategoride henüz ilan bulunmuyor.</p>
                <Link href="/post-ad" className="btn btn-primary" style={{ marginTop: "1rem" }}>
                  İlan Ver
                </Link>
              </div>
            ) : (
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: "1rem" }}>
                {featuredAds.map((ad) => {
                  const remaining = daysLeft(ad.expiresAt);
                  return (
                    <Link key={ad.id} href={`/ad/${ad.id}`} style={{ textDecoration: "none", color: "inherit" }} className="ad-home-card-link">
                      <div className="card ad-home-card" style={{
                        display: "flex",
                        flexDirection: "column",
                        height: "100%",
                        overflow: "hidden"
                      }}>
                        <div style={{ position: "relative", paddingTop: "60%", background: "var(--bg-secondary)" }}>
                          {ad.images && ad.images.length > 0 ? (
                            <Image src={ad.images[0]} alt={ad.title} fill style={{ objectFit: "cover" }} />
                          ) : (
                            <div style={{ position: "absolute", top: 0, left: 0, width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "2.5rem" }}>
                              {ad.category.icon}
                            </div>
                          )}
                          <span style={{ position: "absolute", top: "8px", left: "8px", background: "rgba(0,0,0,0.6)", backdropFilter: "blur(4px)", color: "white", fontSize: "0.7rem", padding: "2px 8px", borderRadius: "100px" }}>
                            {ad.category.icon} {ad.category.name}
                          </span>
                          {ad._count.bids > 0 && (
                            <span style={{ position: "absolute", top: "8px", right: "8px", background: "rgba(0,188,212,0.85)", backdropFilter: "blur(4px)", color: "white", fontSize: "0.7rem", padding: "2px 8px", borderRadius: "100px" }}>
                              🔨 {ad._count.bids} teklif
                            </span>
                          )}
                        </div>
                        <div style={{ padding: "0.75rem", display: "flex", flexDirection: "column", flex: 1 }}>
                          <div style={{ fontWeight: 700, fontSize: "0.9rem", marginBottom: "0.25rem", display: "-webkit-box", WebkitLineClamp: 1, WebkitBoxOrient: "vertical", overflow: "hidden" }}>
                            {ad.title}
                          </div>
                          <div style={{ fontSize: "0.78rem", color: "var(--text-muted)", marginBottom: "0.5rem", display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden", lineHeight: 1.5 }}>
                            {ad.description}
                          </div>
                          <div style={{ marginTop: "auto", display: "flex", justifyContent: "space-between", alignItems: "flex-end" }}>
                            <div>
                              <div style={{ fontWeight: 700, color: "var(--primary)", fontSize: "1rem" }}>
                                {ad.bids?.length > 0 ? `Güncel ${formatPrice(ad.bids[0].amount)}` : (ad.isFixedPrice ? formatPrice(ad.price) : (ad.startingBid === null ? "🔥 Serbest" : formatPrice(ad.startingBid)))}
                              </div>
                              <div style={{ fontSize: "0.72rem", color: "var(--text-muted)" }}>
                                📍 {ad.province.name} · {timeAgo(ad.createdAt)} önce
                              </div>
                            </div>
                            {remaining !== null && remaining <= 5 && (
                              <span style={{ fontSize: "0.7rem", padding: "2px 8px", borderRadius: "100px", background: "rgba(239,68,68,0.1)", color: "#ef4444" }}>
                                ⏱ {remaining} gün
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>
            )}

            {!activeCategory && latestAds.length > 0 && (
              <section style={{ marginTop: "3rem" }}>
                <div className="section-header" style={{ marginBottom: "1rem" }}>
                  <h2 className="section-title" style={{ fontSize: "1.25rem" }}>🕐 Son Eklenen İlanlar</h2>
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: "0.625rem" }}>
                  {latestAds.map((ad) => (
                    <Link key={ad.id} href={`/ad/${ad.id}`} style={{ textDecoration: "none", color: "inherit" }}>
                      <div className="card" style={{ padding: "0.75rem 1rem" }}>
                        <div style={{ display: "flex", gap: "0.875rem", alignItems: "center" }}>
                          {ad.images && ad.images.length > 0 ? (
                            <Image src={ad.images[0]} alt={ad.title} width={52} height={52} style={{ objectFit: "cover", borderRadius: "var(--radius-md)", flexShrink: 0 }} />
                          ) : (
                            <div style={{ width: "52px", height: "52px", display: "flex", alignItems: "center", justifyContent: "center", background: "var(--bg-secondary)", borderRadius: "var(--radius-md)", fontSize: "1.5rem", flexShrink: 0 }}>
                              {ad.category.icon}
                            </div>
                          )}
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontWeight: 600, fontSize: "0.9rem", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{ad.title}</div>
                            <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                              {ad.description.slice(0, 80)}...
                            </div>
                            <div style={{ fontSize: "0.72rem", color: "var(--text-muted)", marginTop: "2px" }}>
                              📍 {ad.province.name} · {timeAgo(ad.createdAt)} önce
                              {ad._count.bids > 0 && ` · 🔨 ${ad._count.bids} teklif`}
                            </div>
                          </div>
                          <div style={{ textAlign: "right", flexShrink: 0 }}>
                            <div style={{ fontWeight: 700, color: "var(--primary)" }}>
                              {ad.bids?.length > 0 ? `Güncel ${formatPrice(ad.bids[0].amount)}` : (ad.isFixedPrice ? formatPrice(ad.price) : (ad.startingBid === null ? "🔥 Serbest" : formatPrice(ad.startingBid)))}
                            </div>
                            <span style={{ fontSize: "0.7rem", padding: "1px 6px", background: "rgba(0,188,212,0.08)", borderRadius: "100px", color: "var(--primary)" }}>
                              {ad.category.icon} {ad.category.name}
                            </span>
                          </div>
                        </div>
                      </div>
                    </Link>
                  ))}
                </div>
              </section>
            )}
          </div>
        </div>
      </div>

      <div style={{ height: "4rem" }} />
    </>
  );
}
