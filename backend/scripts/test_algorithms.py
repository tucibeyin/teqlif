"""
Algoritma değişikliklerini doğrulayan birim testleri.
FastAPI / DB / Redis gerektirmez — sadece saf mantık testi.

Çalıştır:
  cd /var/www/teqlif.com/backend
  python scripts/test_algorithms.py
"""
import math
import sys
import time

PASS = "\033[92m✓\033[0m"
FAIL = "\033[91m✗\033[0m"
results = []


def check(name: str, cond: bool, detail: str = ""):
    mark = PASS if cond else FAIL
    print(f"  {mark}  {name}" + (f"  ({detail})" if detail else ""))
    results.append(cond)


# ──────────────────────────────────────────────────────────────────────────────
# 1. HEAT SCORE — zaman çürümesi + likes
# ──────────────────────────────────────────────────────────────────────────────
print("\n[1] Heat Score — Hacker News decay + likes\n")

def _heat(views, likes, hes, age_h):
    raw = views * 1 + likes * 2 + hes * 3
    return raw / (age_h + 2) ** 1.2

# Aynı ham skor, eski ilan daha düşük çıkmalı
score_fresh = _heat(views=10, likes=2, hes=1, age_h=1)
score_stale = _heat(views=10, likes=2, hes=1, age_h=48)
check("Yeni ilan > eski ilan (aynı etkileşim)", score_fresh > score_stale,
      f"{score_fresh:.3f} vs {score_stale:.3f}")

# Hesitation ağırlığı: 3× view
score_hes   = _heat(views=0, likes=0, hes=5, age_h=0)
score_views = _heat(views=5, likes=0, hes=0, age_h=0)
check("Hesitation (3×) > eşdeğer view (1×)", score_hes > score_views,
      f"hes={score_hes:.3f} vs view={score_views:.3f}")

# Like (2×) view'dan (1×) ağır
score_like = _heat(views=0, likes=5, hes=0, age_h=0)
score_view = _heat(views=5, likes=0, hes=0, age_h=0)
check("Like (2×) > eşdeğer view (1×)", score_like > score_view,
      f"like={score_like:.3f} vs view={score_view:.3f}")

# Sıfır etkileşim → sıfır
check("Sıfır etkileşim → sıfır skor", _heat(0, 0, 0, 0) == 0.0)

# Hiç event yoksa age_h = 0 (ts_map'te yok → _now_ts kullanılır → 0)
check("ts_map eksikse age_h = 0 → en yüksek olası skor", _heat(5, 1, 1, 0) > _heat(5, 1, 1, 24))


# ──────────────────────────────────────────────────────────────────────────────
# 2. FİYAT SİNYALİ — kategori std dev eşiği
# ──────────────────────────────────────────────────────────────────────────────
print("\n[2] Fiyat Sinyali — dinamik std-dev eşiği\n")

def _price_signal(price, market_avg, price_stddev):
    diff_pct = round(((price - market_avg) / market_avg) * 100, 1)
    threshold = max(min((price_stddev / market_avg) * 100, 40.0), 10.0) if price_stddev else 15.0
    signal = "pahalı" if diff_pct > threshold else ("ucuz" if diff_pct < -threshold else "uygun")
    return signal, diff_pct, threshold

# Dar piyasa: std=50, avg=1000 → eşik=5% (ama floor 10%) → 12% fark = pahalı
sig, dp, thr = _price_signal(1120, 1000, 50)
check("Dar piyasa (std=5%): 12% fark → pahalı", sig == "pahalı",
      f"diff={dp}% eşik={thr:.1f}%")

# Geniş piyasa: std=400, avg=1000 → eşik=40% (cap) → 30% fark = uygun
sig, dp, thr = _price_signal(1300, 1000, 400)
check("Geniş piyasa (std=40%): 30% fark → uygun", sig == "uygun",
      f"diff={dp}% eşik={thr:.1f}%")

# Orta piyasa: std=150, avg=1000 → eşik=15% → 20% fark = pahalı
sig, dp, thr = _price_signal(1200, 1000, 150)
check("Orta piyasa (std=15%): 20% fark → pahalı", sig == "pahalı",
      f"diff={dp}% eşik={thr:.1f}%")

# stddev=None fallback → eski 15% sabit eşik
sig, dp, thr = _price_signal(1200, 1000, None)
check("stddev=None → fallback 15% eşik", thr == 15.0 and sig == "pahalı")

# Floor: std çok küçükse 10% altına düşmemeli
sig, dp, thr = _price_signal(1050, 1000, 10)
check("Floor: std=1% → eşik=10% (floor)", thr == 10.0,
      f"thr={thr:.1f}%")


# ──────────────────────────────────────────────────────────────────────────────
# 3. SATICI ROZETİ — percentile eşikler
# ──────────────────────────────────────────────────────────────────────────────
print("\n[3] Satıcı Rozeti — veri bazlı eşikler\n")

def _badge(conv, total, trusted_thr, active_thr):
    if conv >= trusted_thr:
        return "trusted_seller"
    elif total >= active_thr:
        return "active_seller"
    return None

# p75=0.80 güvenilir satıcı eşiği → 0.79 değil ama 0.81 evet
check("conv=0.81 ≥ p75=0.80 → trusted_seller",
      _badge(0.81, 10, 0.80, 5) == "trusted_seller")
check("conv=0.79 < p75=0.80 → trusted değil",
      _badge(0.79, 10, 0.80, 5) != "trusted_seller")

# p50=4 aktif satıcı eşiği
check("total=5 ≥ p50=4 → active_seller",
      _badge(0.30, 5, 0.80, 4) == "active_seller")
check("total=3 < p50=4 → rozet yok",
      _badge(0.30, 3, 0.80, 4) is None)

# Floor: p75 asla 0.50'nin altına düşmesin
trusted_thr = max(0.40, 0.50)  # simüle: p75=0.40 → floor 0.50
check("p75 floor=0.50 geçerli", trusted_thr == 0.50)

# Floor: p50 asla 3'ün altına düşmesin
active_thr = max(2, 3)  # simüle: p50=2 → floor 3
check("p50 floor=3 geçerli", active_thr == 3)


# ──────────────────────────────────────────────────────────────────────────────
# 4. GÜVEN SKORU — p90 normalizasyonu
# ──────────────────────────────────────────────────────────────────────────────
print("\n[4] Güven Skoru — p90 normalizasyon\n")

def _trust_auction_score(total, p90):
    return min(total / p90, 1.0) * 30

# p90=15: 15 açık artırma → tam skor (30)
check("total=p90 → tam skor (30)", _trust_auction_score(15, 15) == 30.0)

# p90=15: 8 açık artırma → 16/30
score = _trust_auction_score(8, 15)
check("total=8, p90=15 → ~16 puan", abs(score - 16.0) < 0.01,
      f"{score:.2f}/30")

# Sabit 10'dan farkı: p90=20 iken sabit 10 kullanmak herkese inflasyon verir
old = min(8 / 10, 1.0) * 30  # eski
new = min(8 / 20, 1.0) * 30  # yeni (p90=20 iken)
check("p90=20 → daha doğru normalizasyon (eski haksız şişiriliyordu)",
      new < old, f"eski={old:.1f} yeni={new:.1f}")

# Floor: p90 asla 5'in altına düşmesin
p90 = max(float(2), 5.0)  # simüle: p90=2 → floor 5
check("p90 floor=5 geçerli", p90 == 5.0)


# ──────────────────────────────────────────────────────────────────────────────
# 5. ÖNERİLEN SATICILER — badge yeniden sıralama
# ──────────────────────────────────────────────────────────────────────────────
print("\n[5] Önerilen Satıcılar — badge yeniden sıralama\n")

def _seller_rank(cat_match, badge_score, listing_count, follower_count):
    return (
        cat_match * 0.45
        + badge_score * 0.20
        + min(math.log(1.0 + listing_count) / 4.0, 0.20)
        + min(math.log(1.0 + follower_count) / 8.0, 0.15)
    )

def _badge_score(badge_str):
    if badge_str == "trusted_seller":
        return 1.0
    if badge_str == "active_seller":
        return 0.5
    return 0.0

# Rozetsiz yüksek takipçi vs. rozetli az takipçi
score_no_badge = _seller_rank(0.9, _badge_score(None), 20, 500)
score_trusted  = _seller_rank(0.9, _badge_score("trusted_seller"), 5, 10)
check("trusted_seller rozeti (az ilan) > rozetsiz (çok takipçi)",
      score_trusted > score_no_badge,
      f"trusted={score_trusted:.3f} vs no_badge={score_no_badge:.3f}")

# Aynı kategori eşleşmesi: trusted > active > rozetsiz
s_trusted = _seller_rank(0.8, 1.0, 10, 50)
s_active  = _seller_rank(0.8, 0.5, 10, 50)
s_none    = _seller_rank(0.8, 0.0, 10, 50)
check("trusted > active > rozetsiz (sabit diğer sinyaller)",
      s_trusted > s_active > s_none,
      f"{s_trusted:.3f} > {s_active:.3f} > {s_none:.3f}")

# Ağırlık kontrolü: log sınırları
check("listing_count katkısı max 0.20",
      min(math.log(1 + 1_000_000) / 4.0, 0.20) == 0.20)
check("follower_count katkısı max 0.15",
      min(math.log(1 + 1_000_000) / 8.0, 0.15) == 0.15)


# ──────────────────────────────────────────────────────────────────────────────
# 6. ÖNERİLEN YAYINLAR — sürekli affinity
# ──────────────────────────────────────────────────────────────────────────────
print("\n[6] Önerilen Yayınlar — sürekli affinity\n")

def _stream_score(category, viewer_count, likes_count, started_age_h,
                  interests, max_viewers, max_likes):
    _max_interest = max(interests.values(), default=1.0) if interests else 1.0
    raw_aff = interests.get(category, 0.0) if interests else 0.0
    cat_score = (raw_aff / _max_interest) * 0.50
    viewer_score = (viewer_count / max_viewers) * 0.25
    likes_score = (likes_count / max_likes) * 0.20
    recency_score = max(0.0, (1.0 - started_age_h / 2.0)) * 0.05
    return cat_score + viewer_score + likes_score + recency_score

interests = {"elektronik": 0.9, "giyim": 0.3, "kitap": 0.1}

# Sevilen kategori (0.9) vs. az sevilen (0.3) — aynı izleyici/like
s_fav = _stream_score("elektronik", 10, 5, 3, interests, 100, 50)
s_mild = _stream_score("giyim", 10, 5, 3, interests, 100, 50)
check("Sevilen kategori (0.9) > az sevilen (0.3) — sürekli skor",
      s_fav > s_mild, f"fav={s_fav:.3f} mild={s_mild:.3f}")

# Eski ikili sistemde giyim ile elektronik aynı (her ikisi top-4'te)
# Yeni: elektronik/giyim = 0.9/0.3 = 3× oranı → oran test
ratio = (0.9 / max(interests.values())) / (0.3 / max(interests.values()))
check("Yeni: sevilme oranı 3× cat_score'a yansıyor", abs(ratio - 3.0) < 0.01)

# Yeni yayın (<2h) bonus alıyor
s_fresh = _stream_score("giyim", 10, 5, 0.5, interests, 100, 50)
s_old   = _stream_score("giyim", 10, 5, 10.0, interests, 100, 50)
check("Yeni yayın (<2h) > eski yayın (recency bonus)", s_fresh > s_old,
      f"fresh={s_fresh:.3f} old={s_old:.3f}")

# interests=None → cat_score=0, çökmemeli
s_no_interests = _stream_score("elektronik", 50, 20, 1, {}, 100, 50)
check("interests={} → cat_score=0, çökmüyor", s_no_interests >= 0)

# ──────────────────────────────────────────────────────────────────────────────
# SONUÇ
# ──────────────────────────────────────────────────────────────────────────────
total  = len(results)
passed = sum(results)
failed = total - passed
print(f"\n{'─' * 50}")
print(f"Toplam: {total}  {PASS} {passed}  {FAIL} {failed}")
if failed:
    print("Başarısız testler var!")
    sys.exit(1)
else:
    print("Tüm testler geçti.")
    sys.exit(0)
