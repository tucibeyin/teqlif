import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { categories } from "@/lib/categories";

async function getAds(categorySlug?: string) {
  try {
    const where = categorySlug
      ? { category: { slug: categorySlug }, status: "ACTIVE" as const }
      : { status: "ACTIVE" as const };

    return await prisma.ad.findMany({
      where,
      take: 30,
      orderBy: { createdAt: "desc" },
      include: {
        user: { select: { name: true } },
        category: true,
        province: true,
        district: true,
        _count: { select: { bids: true } },
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

export default async function HomePage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>;
}) {
  const params = await searchParams;
  const activeCategory = params.category;
  const ads = await getAds(activeCategory);

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

      <div className="container">
        {/* Kategoriler */}
        <div className="section-header" style={{ marginBottom: "0.75rem" }}>
          <h2 className="section-title">Kategoriler</h2>
        </div>
        <div className="categories-scroll" style={{ marginBottom: "2.5rem" }}>
          <Link
            href="/"
            className={`category-chip ${!activeCategory ? "active" : ""}`}
          >
            🏷️ Tümü
          </Link>
          {categories.map((cat) => (
            <Link
              key={cat.slug}
              href={`/?category=${cat.slug}`}
              className={`category-chip ${activeCategory === cat.slug ? "active" : ""}`}
            >
              {cat.icon} {cat.name}
            </Link>
          ))}
        </div>

        {/* İlanlar */}
        <section id="ilanlar" className="section" style={{ paddingTop: "0" }}>
          <div className="section-header">
            <h2 className="section-title">
              {activeCategory
                ? categories.find((c) => c.slug === activeCategory)?.name + " İlanları"
                : "Son İlanlar"}
            </h2>
            <span className="text-sm text-muted">{ads.length} ilan</span>
          </div>

          {ads.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">📭</div>
              <div className="empty-state-title">Henüz ilan yok</div>
              <p>Bu kategoride ilan bulunmuyor. İlk ilanı sen ekle!</p>
              <Link href="/post-ad" className="btn btn-primary" style={{ marginTop: "1rem" }}>
                İlan Ver
              </Link>
            </div>
          ) : (
            <div className="ads-grid">
              {ads.map((ad) => (
                <Link key={ad.id} href={`/ad/${ad.id}`} className="ad-card">
                  {ad.images && ad.images.length > 0 ? (
                    <img src={ad.images[0]} alt={ad.title} className="ad-card-image" />
                  ) : (
                    <div className="ad-card-image-placeholder">
                      {ad.category.icon}
                    </div>
                  )}
                  <div className="ad-card-body">
                    <div className="ad-card-title">{ad.title}</div>
                    <div className="ad-card-price">{formatPrice(ad.price)}</div>
                    <div className="ad-card-meta">
                      <span>📍 {ad.province.name}, {ad.district.name}</span>
                      <span>·</span>
                      <span>{timeAgo(ad.createdAt)}</span>
                    </div>
                    <div style={{ marginTop: "0.5rem" }}>
                      <span className="ad-card-badge">
                        {ad.category.icon} {ad.category.name}
                      </span>
                    </div>
                  </div>
                  {ad._count.bids > 0 && (
                    <div className="ad-card-auction">
                      🔨 <span className="bid-count">{ad._count.bids} teklif</span>
                      <span className="text-muted">· Açık artırma</span>
                    </div>
                  )}
                </Link>
              ))}
            </div>
          )}
        </section>
      </div>
    </>
  );
}
