"""
Listing Quality Score Servisi

İki aşamalı yaklaşım:
  1. Rule-based skor — anında, model gerektirmez (ilan oluşturulunca)
  2. ML-iyileştirilmiş skor — haftalık eğitilen GradientBoosting modeli
     gerçek engagement verisini (beğeni, favori, chat) öğrenir.

Model dosyası: .model_cache/quality_model.pkl
Boyut: ~1 MB | RAM: ~50 MB yüklüyken | Hız: <1ms / ilan
"""
from __future__ import annotations

import json
import logging
import math
import os
import pickle
import threading
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parents[3] / ".model_cache"
_MODEL_PATH = _MODEL_DIR / "quality_model.pkl"
_SCALER_PATH = _MODEL_DIR / "quality_scaler.pkl"

_model: Any = None
_scaler: Any = None
_model_lock = threading.Lock()

FEATURE_COUNT = 15


# ── Özellik çıkarımı ─────────────────────────────────────────────────────────

def extract_features(listing) -> list[float]:
    """
    Bir ilanın içerik özelliklerini 15 boyutlu vektöre çevirir.
    Değerler [0, 1] aralığına normalize edilmiştir.
    """
    title = listing.title or ""
    desc = listing.description or ""

    try:
        imgs = json.loads(listing.image_urls or "[]")
        image_count = len(imgs)
    except Exception:
        image_count = 1 if listing.image_url else 0

    title_len = len(title)
    title_words = len(title.split())
    desc_len = len(desc)
    desc_words = len(desc.split())

    hour = getattr(listing.created_at, "hour", 12) if listing.created_at else 12
    dow = getattr(listing.created_at, "weekday", lambda: 0)() if listing.created_at else 0

    return [
        min(title_len, 200) / 200,           # başlık uzunluğu
        min(title_words, 30) / 30,            # başlık kelime sayısı
        min(desc_len, 2000) / 2000,           # açıklama uzunluğu
        min(desc_words, 300) / 300,            # açıklama kelime sayısı
        min(image_count, 10) / 10,            # fotoğraf sayısı
        1.0 if listing.video_url else 0.0,    # video var mı
        1.0 if listing.price is not None else 0.0,  # fiyat girilmiş mi
        math.log1p(listing.price or 0) / 15, # fiyat büyüklüğü (log)
        1.0 if listing.location else 0.0,     # konum girilmiş mi
        1.0 if listing.category else 0.0,     # kategori seçilmiş mi
        1.0 if listing.brand else 0.0,        # marka girilmiş mi
        1.0 if listing.model_name else 0.0,   # model girilmiş mi
        1.0 if listing.condition else 0.0,    # durum seçilmiş mi
        hour / 23.0,                          # yayın saati
        dow / 6.0,                            # yayın günü
    ]


# ── Rule-based skor (model yoksa) ────────────────────────────────────────────

def _rule_based_score(listing) -> float:
    """
    ML modeli eğitilmeden önce kullanılan kural tabanlı skor.
    Ağırlıklı özellik toplamı → [0, 1].
    """
    title = listing.title or ""
    desc = listing.description or ""

    try:
        imgs = json.loads(listing.image_urls or "[]")
        img_count = len(imgs)
    except Exception:
        img_count = 1 if listing.image_url else 0

    score = 0.0

    # Başlık (0–25 puan)
    tlen = len(title)
    if tlen >= 10:
        score += min(tlen / 60, 1.0) * 25
    else:
        score += (tlen / 10) * 10

    # Açıklama (0–20 puan)
    score += min(len(desc) / 300, 1.0) * 20

    # Fotoğraf (0–20 puan)
    score += min(img_count / 5, 1.0) * 20

    # Fiyat (10 puan)
    if listing.price is not None:
        score += 10

    # Konum (10 puan)
    if listing.location:
        score += 10

    # Video (8 puan)
    if listing.video_url:
        score += 8

    # Marka / model / durum (2+2+2 = 6 puan)
    if listing.brand:
        score += 2
    if listing.model_name:
        score += 2
    if listing.condition:
        score += 2

    # Kategori (7 puan)
    if listing.category:
        score += 7

    return round(score / 100.0, 4)


# ── Model yükleme (singleton) ─────────────────────────────────────────────────

def _load_model() -> tuple[Any, Any]:
    global _model, _scaler
    if _model is not None:
        return _model, _scaler
    with _model_lock:
        if _model is not None:
            return _model, _scaler
        if _MODEL_PATH.exists() and _SCALER_PATH.exists():
            try:
                with open(_MODEL_PATH, "rb") as f:
                    _model = pickle.load(f)
                with open(_SCALER_PATH, "rb") as f:
                    _scaler = pickle.load(f)
                logger.info("[Quality] ML modeli yüklendi: %s", _MODEL_PATH)
            except Exception as exc:
                logger.warning("[Quality] ML modeli yüklenemedi: %s", exc)
                _model = None
                _scaler = None
    return _model, _scaler


# ── Tahmin ───────────────────────────────────────────────────────────────────

def predict_quality(listing) -> float:
    """
    İlanın kalite skorunu döndürür (0.0–1.0).
    ML modeli varsa onu kullanır, yoksa rule-based skora döner.
    """
    model, scaler = _load_model()
    if model is None or scaler is None:
        return _rule_based_score(listing)

    try:
        import numpy as np
        feats = extract_features(listing)
        x = np.array(feats, dtype=np.float32).reshape(1, -1)
        x_scaled = scaler.transform(x)
        raw = float(model.predict(x_scaled)[0])
        return round(max(0.0, min(1.0, raw)), 4)
    except Exception as exc:
        logger.warning("[Quality] Tahmin başarısız, rule-based'e dönülüyor: %s", exc)
        return _rule_based_score(listing)


# ── Model eğitimi ─────────────────────────────────────────────────────────────

async def train_quality_model(db_session) -> int:
    """
    Mevcut ilanların içerik özellikleri + gerçek engagement verisiyle
    GradientBoostingRegressor eğitir ve diske kaydeder.

    Dönüş: eğitimde kullanılan örnek sayısı (0 ise model güncellenmedi).
    """
    from sqlalchemy import text
    import numpy as np
    from sklearn.ensemble import GradientBoostingRegressor
    from sklearn.preprocessing import MinMaxScaler

    try:
        rows = await db_session.execute(text("""
            SELECT
                l.id,
                l.title,
                l.description,
                l.price,
                l.category,
                l.brand,
                l.model_name,
                l.condition,
                l.location,
                l.image_url,
                l.image_urls,
                l.video_url,
                l.created_at,
                -- Engagement target
                COALESCE(lk.like_count, 0) * 1.0
                + COALESCE(ae_fav.cnt, 0) * 2.0
                + COALESCE(ae_chat.cnt, 0) * 3.0
                + COALESCE(ae_offer.cnt, 0) * 5.0  AS engagement
            FROM listings l
            LEFT JOIN (
                SELECT listing_id, COUNT(*) AS like_count
                FROM listing_likes GROUP BY listing_id
            ) lk ON lk.listing_id = l.id
            LEFT JOIN (
                SELECT item_id, COUNT(*) AS cnt
                FROM analytics_events
                WHERE event_type = 'listing_favorite'
                GROUP BY item_id
            ) ae_fav ON ae_fav.item_id = l.id
            LEFT JOIN (
                SELECT item_id, COUNT(*) AS cnt
                FROM analytics_events
                WHERE event_type = 'listing_chat_open'
                GROUP BY item_id
            ) ae_chat ON ae_chat.item_id = l.id
            LEFT JOIN (
                SELECT item_id, COUNT(*) AS cnt
                FROM analytics_events
                WHERE event_type = 'listing_offer_submit'
                GROUP BY item_id
            ) ae_offer ON ae_offer.item_id = l.id
            WHERE l.status != 'deleted'
              AND l.created_at < NOW() - INTERVAL '3 days'
            LIMIT 100000
        """))
        data = rows.fetchall()
    except Exception as exc:
        logger.error("[Quality] Eğitim verisi çekilemedi: %s", exc)
        return 0

    if len(data) < 50:
        logger.warning("[Quality] Yetersiz eğitim verisi (%d örnek), model güncellenmedi.", len(data))
        return 0

    class _FakeListing:
        __slots__ = [
            "title", "description", "price", "category", "brand",
            "model_name", "condition", "location", "image_url",
            "image_urls", "video_url", "created_at",
        ]

    X, y = [], []
    for row in data:
        fl = _FakeListing()
        fl.title = row[1]
        fl.description = row[2]
        fl.price = row[3]
        fl.category = row[4]
        fl.brand = row[5]
        fl.model_name = row[6]
        fl.condition = row[7]
        fl.location = row[8]
        fl.image_url = row[9]
        fl.image_urls = row[10]
        fl.video_url = row[11]
        fl.created_at = row[12]
        X.append(extract_features(fl))
        y.append(float(row[13]))

    X = np.array(X, dtype=np.float32)
    y = np.array(y, dtype=np.float32)

    # Hedefi 0-1'e normalize et
    y_max = max(y.max(), 1.0)
    y_norm = y / y_max

    scaler = MinMaxScaler()
    X_scaled = scaler.fit_transform(X)

    model = GradientBoostingRegressor(
        n_estimators=100,
        max_depth=4,
        learning_rate=0.1,
        subsample=0.8,
        random_state=42,
    )
    model.fit(X_scaled, y_norm)

    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    with open(_MODEL_PATH, "wb") as f:
        pickle.dump(model, f)
    with open(_SCALER_PATH, "wb") as f:
        pickle.dump(scaler, f)

    # Singleton'ı sıfırla — bir sonraki predict yeni modeli yükler
    global _model, _scaler
    _model = None
    _scaler = None

    logger.info("[Quality] Model eğitildi ve kaydedildi. Örnek: %d", len(X))
    return len(X)
