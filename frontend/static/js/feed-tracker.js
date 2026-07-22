/**
 * Feed Tracker — Kişiselleştirme sinyalleri toplama.
 *
 * Kullanım:
 *   FeedTracker.observe(containerEl);   // Feed card'larını gözlemle
 *   FeedTracker.trackOpen(listingId, category);   // İlan açıldığında
 *   FeedTracker.trackClose(listingId, category, dwellSeconds);  // İlan kapandığında
 *   FeedTracker.trackPhotoSwipe(listingId, swipeCount);
 *   FeedTracker.trackVideoWatch(listingId, watchPct);
 *
 * IntersectionObserver ile:
 *   - Kart < 1.5 sn görünürde kalırsa → listing_skip
 *   - Kart >= 1.5 sn görünürde kalırsa → feed_impression
 */
window.FeedTracker = (function () {
    const SKIP_THRESHOLD_MS = 1500;  // 1.5 sn altı = skip
    const _timers = new Map();       // listing_id → { enterTime, category }

    function _hasConsent() {
        return _storage.getItem('teqlif_cookie_consent') === 'accepted';
    }

    function _track(eventType, metadata) {
        if (!_hasConsent()) return;
        if (typeof window.teqlifTrackEvent === 'function') {
            window.teqlifTrackEvent(eventType, metadata);
        }
    }

    /**
     * Feed container'ındaki .feed-card elemanlarını IntersectionObserver ile izler.
     * Her card'ın data-listing-id ve data-category attribute'u olmalı.
     */
    function observe(containerEl) {
        if (!containerEl) return;

        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                const el = entry.target;
                const lid = parseInt(el.dataset.listingId, 10);
                const cat = el.dataset.category || '';

                if (entry.isIntersecting) {
                    _timers.set(lid, { enterTime: Date.now(), category: cat });
                } else {
                    const info = _timers.get(lid);
                    if (!info) return;
                    const elapsed = Date.now() - info.enterTime;
                    _timers.delete(lid);

                    if (elapsed < SKIP_THRESHOLD_MS) {
                        _track('listing_skip', { listing_id: lid, category: info.category });
                    } else {
                        _track('feed_impression', { listing_id: lid, category: info.category });
                    }
                }
            });
        }, { threshold: 0.5 });  // card'ın %50'si görünürde olmalı

        containerEl.querySelectorAll('.feed-card').forEach(card => observer.observe(card));
        return observer;
    }

    /** İlan detay sayfası açıldığında çağrılır. Dwell timer başlatır. */
    function trackOpen(listingId, category) {
        if (!listingId) return;
        sessionStorage.setItem(`dwell_${listingId}`, JSON.stringify({
            start: Date.now(), category: category || ''
        }));
    }

    /** İlan detay sayfasından çıkıldığında çağrılır. */
    function trackClose(listingId, category, forceDwellSeconds) {
        if (!listingId) return;
        let dwellSec = forceDwellSeconds;
        if (!dwellSec) {
            const stored = sessionStorage.getItem(`dwell_${listingId}`);
            if (stored) {
                const info = JSON.parse(stored);
                dwellSec = Math.round((Date.now() - info.start) / 1000);
                category = category || info.category;
                sessionStorage.removeItem(`dwell_${listingId}`);
            }
        }
        if (!dwellSec || dwellSec < 1) return;
        _track('listing_view', {
            listing_id: listingId,
            category: category || '',
            dwell_seconds: dwellSec,
        });
    }

    /** Fotoğraf kaydırmada çağrılır. */
    function trackPhotoSwipe(listingId, swipeCount) {
        if (!listingId || swipeCount < 1) return;
        _track('listing_photo_swipe', {
            listing_id: listingId,
            swipe_count: swipeCount,
        });
    }

    /** Video izlemede çağrılır (0-100 yüzde). */
    function trackVideoWatch(listingId, watchPct) {
        if (!listingId) return;
        _track('listing_video_watch', {
            listing_id: listingId,
            watch_pct: Math.round(watchPct),
        });
    }

    return { observe, trackOpen, trackClose, trackPhotoSwipe, trackVideoWatch };
})();
