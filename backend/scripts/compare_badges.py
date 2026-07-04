"""
Keşfet (for-you feed) ve İlanlar (Son İlanlar) badge karşılaştırması.

VPS'de çalıştır:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/compare_badges.py [user_id]

user_id opsiyonel — verilmezse Son İlanlar (misafir modu) ile karşılaştırır.
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

USER_ID = int(sys.argv[1]) if len(sys.argv) > 1 else None


def badge_str(item: dict) -> str:
    parts = []
    if item.get("is_sponsored"):    parts.append("Sponsorlu")
    if item.get("seller_is_premium"): parts.append("👑PRO")
    b = item.get("seller_badge")
    if b == "trusted_seller":       parts.append("✅trusted")
    elif b == "active_seller":      parts.append("⭐active")
    if item.get("is_trending"):     parts.append("🔥trending")
    if item.get("is_highlight"):    parts.append("🔴highlight")
    return ", ".join(parts) if parts else "—"


def print_table(title: str, items: list[dict]) -> None:
    print(f"\n{'━'*70}")
    print(f"  {title}  ({len(items)} ilan)")
    print(f"{'━'*70}")
    print(f"{'ID':>5}  {'Satıcı':<14}  {'Başlık':<22}  Badges")
    print(f"{'─'*70}")
    for it in items:
        uid   = it.get("user", {}).get("id", "?")
        uname = (it.get("user", {}).get("username") or "")[:14]
        title_ = (it.get("title") or "")[:22]
        print(f"{it['id']:>5}  {uname:<14}  {title_:<22}  {badge_str(it)}")
    print()


async def main() -> None:
    from app.database import AsyncSessionLocal
    from app.services.listing_service import ListingService
    from app.services.feed_service import get_foryou_feed, get_mixed_recent_feed

    async with AsyncSessionLocal() as db:

        # ── 1. Son İlanlar (/listings) ────────────────────────────────────
        svc = ListingService(db)
        recent = await svc.get_listings(current_user_id=USER_ID)
        print_table("SON İLANLAR  (/listings)", recent[:20])

        # ── 2. For-You Feed (/feed/for-you) — yalnızca user_id verilmişse ─
        if USER_ID:
            foryou = await get_foryou_feed(USER_ID, page=0, db=db)
            print_table(f"KEŞFET — FOR-YOU  (user_id={USER_ID})", foryou)
        else:
            mixed = await get_mixed_recent_feed(user_id=None, page=0, db=db)
            print_table("KEŞFET — MİSAFİR  (/feed/mixed-recent)", mixed)

        # ── 3. Redis özeti ────────────────────────────────────────────────
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        badge_keys = [k async for k in redis.scan_iter("seller:badge:*")]
        trending   = await redis.smembers("trending:categories")

        print(f"{'━'*70}")
        print(f"  REDİS ÖZET")
        print(f"{'━'*70}")
        if badge_keys:
            for k in sorted(badge_keys):
                v = await redis.get(k)
                print(f"  {k:<28} → {v}")
        else:
            print("  (rozet yok)")
        print(f"  trending:categories        → {trending or '(yok)'}")
        print()


asyncio.run(main())
