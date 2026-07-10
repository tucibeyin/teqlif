"""
Churn ML Servisi — GradientBoostingClassifier tabanlı churn tespiti.

Mevcut heuristik (analytics_tasks.py) kural tabanlıdır: 5 gün inaktif + %70 dwell düşüşü.
Bu servis ClickHouse'daki son 90 günlük davranış verisinden çok sinyalli özellik matrisi oluşturur
ve GradientBoosting modeli eğitir. Model pickle dosyasına yazılır; analytics_tasks.py
model mevcutsa ML tahminlerini, yoksa mevcut heuristiği kullanır.

Model dosyası: /var/www/teqlif.com/models/churn_model.pkl
Eğitim frekansı: ARQ cron, her Pazartesi 05:00

Özellikler (8 adet):
  1. days_since_last_event     — son etkinlikten bu yana geçen gün
  2. avg_dwell_last_7d         — son 7 günün ortalama dwell süresi (ms)
  3. avg_dwell_prev_7d         — 7–14 gün öncesinin ortalaması (trend için)
  4. click_rate                — impression başına tıklama oranı (son 30 gün)
  5. search_count_14d          — son 14 günde yapılan arama sayısı
  6. bid_count_30d             — son 30 günde teklif sayısı
  7. session_days_7d           — son 7 günde kaç farklı günde aktif olundu
  8. hesitation_to_bid_ratio   — bid_hesitation / (bid_placed + 1)

Label: kullanıcı mevcut pencerede aktif, ama 14 gün sonrasında hiç etkinlik yok → churn=1
(Gerçek label hesaplaması: son 30+14 gün penceresi — önceki 30 gün aktif, son 14 gün sessiz)
"""
from __future__ import annotations

import asyncio
import logging
import os
import pickle
from pathlib import Path
from typing import TYPE_CHECKING

logger = logging.getLogger(__name__)

_MODEL_DIR  = Path("/var/www/teqlif.com/models")
_MODEL_PATH = _MODEL_DIR / "churn_model.pkl"
_MIN_SAMPLES = 200  # Bu kadar örnek yoksa eğitimi atla


def _model_path() -> Path:
    """VPS ortamında gerçek path; geliştirmede /tmp'ye düşer."""
    if _MODEL_DIR.exists():
        return _MODEL_PATH
    fallback = Path("/tmp/teqlif_churn_model.pkl")
    return fallback


async def _fetch_features() -> tuple[list[list[float]], list[int]]:
    """
    ClickHouse'dan özellik matrisi ve etiket listesi oluşturur.
    Döner: (X, y) — X: [[f1..f8], ...], y: [0|1, ...]
    """
    from app.database_clickhouse import get_clickhouse_client

    ch = await get_clickhouse_client()
    if ch is None:
        return [], []

    result = await ch.query("""
        WITH
            base AS (
                SELECT
                    user_id,
                    max(timestamp)                                             AS last_ts,
                    dateDiff('day', max(timestamp), now())                     AS days_since_last,
                    avgIf(duration_seconds, event_type='impression'
                          AND timestamp >= now() - INTERVAL 7 DAY)             AS avg_dwell_7d,
                    avgIf(duration_seconds, event_type='impression'
                          AND timestamp >= now() - INTERVAL 14 DAY
                          AND timestamp <  now() - INTERVAL 7 DAY)             AS avg_dwell_prev,
                    countIf(event_type='click'
                            AND timestamp >= now() - INTERVAL 30 DAY)          AS clicks_30d,
                    countIf(event_type='impression'
                            AND timestamp >= now() - INTERVAL 30 DAY)          AS imps_30d,
                    countIf(event_type='bid_placed'
                            AND timestamp >= now() - INTERVAL 30 DAY)          AS bids_30d,
                    countIf(event_type='bid_hesitation'
                            AND timestamp >= now() - INTERVAL 30 DAY)          AS hes_30d,
                    uniqIf(toDate(timestamp),
                           timestamp >= now() - INTERVAL 7 DAY)                AS active_days_7d
                FROM user_events
                WHERE user_id IS NOT NULL
                  AND timestamp >= now() - INTERVAL 44 DAY
                GROUP BY user_id
                HAVING imps_30d >= 3
            ),
            label_data AS (
                SELECT user_id, count() AS events_future
                FROM user_events
                WHERE user_id IS NOT NULL
                  AND timestamp >= now() - INTERVAL 14 DAY
                GROUP BY user_id
            )
        SELECT
            b.user_id,
            b.days_since_last,
            coalesce(b.avg_dwell_7d,   0),
            coalesce(b.avg_dwell_prev, 0),
            if(b.imps_30d > 0, b.clicks_30d / b.imps_30d, 0),
            b.bids_30d,
            b.active_days_7d,
            b.hes_30d / (b.bids_30d + 1),
            if(l.events_future IS NULL OR l.events_future = 0, 1, 0) AS churn_label
        FROM base b
        LEFT JOIN label_data l ON l.user_id = b.user_id
    """)

    X, y = [], []
    for row in result.result_rows:
        _, *features, label = row
        if None in features:
            continue
        X.append([float(f) for f in features])
        y.append(int(label))

    return X, y


async def train_churn_model() -> bool:
    """
    Modeli eğitir ve diske yazar.
    Döner True → model kaydedildi, False → yetersiz veri.
    """
    import asyncio
    X, y = await _fetch_features()

    if len(X) < _MIN_SAMPLES:
        logger.info("[ChurnML] Yetersiz örnek: %d (min=%d)", len(X), _MIN_SAMPLES)
        return False

    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _train_sync, X, y)
    return True


def _train_sync(X: list[list[float]], y: list[int]) -> None:
    """CPU-yoğun eğitim — executor'da çalışır."""
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import StandardScaler
    import numpy as np

    X_arr = np.array(X, dtype=np.float32)
    y_arr = np.array(y, dtype=np.int32)

    X_tr, X_val, y_tr, y_val = train_test_split(
        X_arr, y_arr, test_size=0.15, random_state=42, stratify=y_arr
    )

    scaler = StandardScaler()
    X_tr  = scaler.fit_transform(X_tr)
    X_val = scaler.transform(X_val)

    clf = GradientBoostingClassifier(
        n_estimators=120,
        max_depth=4,
        learning_rate=0.08,
        subsample=0.8,
        random_state=42,
    )
    clf.fit(X_tr, y_tr)

    val_acc = clf.score(X_val, y_val)
    logger.info("[ChurnML] Validasyon doğruluğu: %.3f | örnekler=%d", val_acc, len(X))

    model_path = _model_path()
    model_path.parent.mkdir(parents=True, exist_ok=True)
    with open(model_path, "wb") as f:
        pickle.dump({"scaler": scaler, "clf": clf, "val_acc": val_acc}, f)
    logger.info("[ChurnML] Model kaydedildi: %s", model_path)


def predict_churn_risk(user_features: list[list[float]]) -> list[float]:
    """
    Kayıtlı modelden churn olasılığı tahmin eder (0.0–1.0).
    Model yoksa boş liste döner → çağıran heuristiğe düşer.
    """
    path = _model_path()
    if not path.exists():
        return []

    try:
        from sklearn.exceptions import NotFittedError
        import numpy as np

        with open(path, "rb") as f:
            bundle = pickle.load(f)

        scaler = bundle["scaler"]
        clf    = bundle["clf"]
        X = scaler.transform(np.array(user_features, dtype=np.float32))
        probs = clf.predict_proba(X)[:, 1]  # sınıf=1 (churn) olasılığı
        return probs.tolist()
    except Exception as exc:
        logger.warning("[ChurnML] predict başarısız: %s", exc)
        return []
