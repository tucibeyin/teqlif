"""
Kullanıcı router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db) alır
  2. UserService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, DB sorguları ve yetki kontrolleri tamamen
app.services.user_service.UserService'e taşınmıştır.
"""
import math
from typing import Optional, List

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text as sa_text

from app.models.enums import UserStatus
from app.database import get_db
from app.models.user import User
from app.models.referral import Referral
from app.schemas.block import BlockedUserOut, BlockStatusOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.services.user_service import UserService
from app.services.referral_service import apply_referral

router = APIRouter(prefix="/api/users", tags=["users"])


class ApplyReferralBody(BaseModel):
    referral_code: str = Field(min_length=4, max_length=12)


# ── Opsiyonel kullanıcı bağımlılığı (unauthenticated profil erişimi) ─────────
async def _optional_user(
    credentials=Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    if not credentials:
        return None
    user_id = decode_token(credentials.credentials)
    if not user_id:
        return None
    result = await db.execute(
        select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)  # noqa: E712
    )
    return result.scalar_one_or_none()


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/blocked", response_model=List[BlockedUserOut])
async def list_blocked_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).list_blocked(current_user)


@router.post("/{username}/block", response_model=BlockStatusOut)
async def block_user(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).block(username, current_user)


@router.delete("/{username}/block", response_model=BlockStatusOut)
async def unblock_user(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).unblock(username, current_user)


@router.post("/apply-referral")
async def apply_referral_code(
    request: Request,
    body: ApplyReferralBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.utils.i18n import get_locale
    lang = get_locale(request=request)
    return await apply_referral(db, current_user, body.referral_code, lang)


from app.services.referral_service import ensure_valid_referral_code

@router.get("/my-referral")
async def my_referral(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının kendi davet kodunu, son kullanma tarihini ve istatistiklerini döner."""
    ref_data = await ensure_valid_referral_code(db, current_user)
    
    total_invited = await db.scalar(
        select(func.count()).where(Referral.referrer_id == current_user.id)
    )
    already_used = await db.scalar(
        select(Referral).where(Referral.referred_id == current_user.id)
    )
    return {
        "referral_code": ref_data["code"],
        "expires_at": ref_data["expires_at"],
        "total_invited": total_invited or 0,
        "referrer_bonus_per_invite": 50,
        "referred_bonus": 10,
        "already_used_a_code": already_used is not None,
    }


@router.get("/suggested-sellers")
async def get_suggested_sellers(
    limit: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Kullanıcının ilgi profiline göre 'Kimi Takip Et' önerilerini döndürür.

    Algoritma:
      1. user_interests → kullanıcının ilgi kategorileri (top-5)
      2. Bu kategorilerde en çok aktif ilan bulunan satıcılar seçilir
      3. Kullanıcının zaten takip ettiği satıcılar hariç tutulur
      4. Sıralama: kategori_eşleşme × ilan_sayısı_skoru × satıcı_kalitesi
    """
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    cached_interests = await redis.get(f"interests:{current_user.id}")
    if cached_interests:
        import json as _json
        interests = _json.loads(cached_interests)
    else:
        rows = await db.execute(
            sa_text("SELECT category, score FROM user_interests WHERE user_id = :uid ORDER BY score DESC LIMIT 5"),
            {"uid": current_user.id},
        )
        interests = {row.category: row.score for row in rows}

    top_cats = list(interests.keys())[:5] if interests else []

    if top_cats:
        cat_cases = " ".join(
            f"WHEN l.category = '{cat}' THEN {score:.4f}"
            for cat, score in list(interests.items())[:5]
        )
        cat_score_expr = f"COALESCE(MAX(CASE {cat_cases} ELSE 0.0 END), 0.0)"
    else:
        cat_score_expr = "0.0"

    base_query = f"""
        SELECT
            u.id,
            u.username,
            u.full_name,
            u.profile_image_url,
            u.bio,
            (u.email_verified AND u.phone_verified) AS is_verified,
            u.is_premium,
            COUNT(l.id)                                     AS listing_count,
            {cat_score_expr}                                AS cat_match,
            COALESCE(fol.follower_count, 0)                 AS follower_count
        FROM users u
        INNER JOIN listings l ON l.user_id = u.id
            AND l.status = 'active' AND l.status != 'deleted'
        LEFT JOIN (
            SELECT followed_id, COUNT(*) AS follower_count
            FROM follows GROUP BY followed_id
        ) fol ON fol.followed_id = u.id
        WHERE u.id != :uid
          AND u.status = 'active'
          AND u.id NOT IN (
              SELECT blocked_id FROM user_blocks WHERE blocker_id = :uid
              UNION
              SELECT blocker_id FROM user_blocks WHERE blocked_id = :uid
          )
        {{follow_filter}}
        GROUP BY u.id, u.username, u.full_name, u.profile_image_url, u.bio, u.email_verified, u.phone_verified, u.is_premium, fol.follower_count
        HAVING COUNT(l.id) >= 1
        ORDER BY (
            {cat_score_expr} * 0.60
            + LEAST(LOG(1.0 + COUNT(l.id)) / 4.0, 0.25)
            + LEAST(LOG(1.0 + COALESCE(fol.follower_count, 0)) / 8.0, 0.15)
        ) DESC
        LIMIT :lim
    """

    fetch_lim = min(limit * 2, 100)
    result = await db.execute(
        sa_text(base_query.format(follow_filter="AND u.id NOT IN (SELECT followed_id FROM follows WHERE follower_id = :uid)")),
        {"uid": current_user.id, "lim": fetch_lim},
    )
    rows_out = result.fetchall()

    # Takip edilmeyenler boşsa takip edilenleri de göster (fallback)
    if not rows_out:
        result = await db.execute(
            sa_text(base_query.format(follow_filter="")),
            {"uid": current_user.id, "lim": fetch_lim},
        )
        rows_out = result.fetchall()

    # Redis'ten satıcı rozeti verisi — badge sinyal ağırlığı
    if rows_out:
        seller_ids = [row[0] for row in rows_out]
        raw_badges = await redis.mget(*[f"seller:badge:{sid}" for sid in seller_ids])

        def _badge_score(b) -> float:
            if b is None:
                return 0.0
            s = b.decode() if isinstance(b, bytes) else str(b)
            return 1.0 if s == "trusted_seller" else (0.5 if s == "active_seller" else 0.0)

        badge_map = {sid: _badge_score(b) for sid, b in zip(seller_ids, raw_badges)}

        def _rank(row) -> float:
            cat_m = float(row[8])
            badge = badge_map.get(row[0], 0.0)
            lst_cnt = int(row[7])
            fol_cnt = int(row[9])
            return (
                cat_m * 0.45
                + badge * 0.20
                + min(math.log(1.0 + lst_cnt) / 4.0, 0.20)
                + min(math.log(1.0 + fol_cnt) / 8.0, 0.15)
            )

        rows_out = sorted(rows_out, key=_rank, reverse=True)[:limit]

    return [
        {
            "id": row[0],
            "username": row[1],
            "full_name": row[2],
            "profile_image_url": row[3],
            "bio": row[4],
            "is_verified": row[5],
            "is_premium": row[6],
            "listing_count": row[7],
            "follower_count": row[9],
        }
        for row in rows_out
    ]


@router.get("/{username}")
async def get_user_profile(
    username: str,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).get_profile(username, current_user)
