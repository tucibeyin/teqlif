import Link from "next/link";
import Image from "next/image";
import { prisma } from "@/lib/prisma";
import { categoryTree, findPath } from "@/lib/categories";
import type { CategoryNode } from "@/lib/categories";

export const dynamic = "force-dynamic";

/** Sidebar kategori node'unu render eder: çocuğu varsa accordion, yoksa link */
function renderSidebarNode(
  node: CategoryNode,
  activeCategory: string | undefined,
  depth = 0
): React.ReactNode {
  const isActive = activeCategory === node.slug;
  const hasActiveDescendant =
    activeCategory !== undefined &&
    !isActive &&
    findPath(activeCategory, node.children) !== null;

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
      open={isActive || hasActiveDescendant || undefined}
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
          renderSidebarNode(child, activeCategory, depth + 1)
        )}
      </div>
    </details>
  );
}

async function getAds(categorySlug?: string, limit = 24) {
  try {
    const where: Record<string, unknown> = {
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
        bids: { orderBy: { amount: "desc" }, take: 1, select: { amount: true } },
      },
    });
  } catch {
    return [];
  }
}

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
  searchParams: Promise<{ category?: string }>;
}) {
  const params = await searchParams;
  const activeCategory = params.category;
  const ads = await getAds(activeCategory, 24);
  const latestAds = activeCategory ? [] : ads.slice(0, 8);
  const featuredAds = activeCategory ? ads : ads.slice(0, 16);

  return (
    <>
      {/* Hero */}
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

      <div className="container" id="ilanlar" style={{ paddingTop: "2rem" }}>
        <div style={{ display: "grid", gridTemplateColumns: "220px 1fr", gap: "2rem", alignItems: "start" }}>

          {/* LEFT SIDEBAR: Categories */}
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
            {/* Tümü linki */}
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
              <span style={{ marginLeft: "auto", fontSize: "0.75rem", color: "var(--text-muted)" }}>{ads.length}</span>
            </Link>

            {/* Kategori listeleme: recursive — çocuklar accordion, yapraklar link */}
            {categoryTree.map((node) => renderSidebarNode(node, activeCategory))}
          </aside>

          {/* MAIN CONTENT */}
          <div>
            {/* Active Category title or Featured */}
            <div className="section-header" style={{ marginBottom: "1rem" }}>
              <h2 className="section-title" style={{ fontSize: "1.25rem" }}>
                {activeCategory
                  ? (() => {
                    const path = findPath(activeCategory, categoryTree);
                    if (!path) return "İlanlar";
                    return path.map((n, i) => i === 0 ? `${n.icon ?? ""} ${n.name}`.trim() : n.name).join(" › ") + " İlanları";
                  })()
                  : "Öne Çıkan İlanlar"}
              </h2>
              <span className="text-sm text-muted">{featuredAds.length} ilan</span>
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
                        {/* Image */}
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
                        {/* Body */}
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

            {/* Latest Ads section - tylko jeśli nie filtrujemy po kategorii */}
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

      {/* Bottom spacing */}
      <div style={{ height: "4rem" }} />
    </>
  );
}
