/**
 * kesfet-page.js — Kişiselleştirilmiş feed
 *
 * Her zaman /api/feed endpoint'ini kullanır.
 * Giriş yapanlar → kategori ilgisine göre sıralı içerik
 * Misafirler → son 30 günün en popüler ilanları
 *
 * Bağımlılıklar: main.js → apiFetch, analytics.js → teqlifTrackEvent
 */
(function () {
    'use strict';

    /* ── Oturum seed'i — aynı scroll oturumunda tutarlı sıralama ── */
    let _seed = sessionStorage.getItem('kesfet_feed_seed');
    if (!_seed) {
        _seed = Math.random().toString(36).slice(2, 10);
        sessionStorage.setItem('kesfet_feed_seed', _seed);
    }

    let _page = 0;
    let _loading = false;
    let _exhausted = false;
    let _scrollObserver = null;
    const _timers = new Map();  // listing_id → { t, cat } (skip/impression ölçümü)

    /* ── Yardımcılar ──────────────────────────────────────────── */
    function esc(s) {
        if (!s) return '';
        return String(s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function fmtPrice(p) {
        if (p == null) return '';
        const s = Math.round(Number(p)).toString();
        let r = '';
        for (let i = 0; i < s.length; i++) {
            if (i > 0 && (s.length - i) % 3 === 0) r += '.';
            r += s[i];
        }
        return r + ' ₺';
    }

    function firstImage(l) {
        if (l.image_urls && l.image_urls.length > 0) return l.image_urls[0];
        return l.image_url || null;
    }

    function track(eventType, metadata) {
        if (localStorage.getItem('teqlif_cookie_consent') !== 'accepted') return;
        if (typeof window.teqlifTrackEvent === 'function') {
            window.teqlifTrackEvent(eventType, metadata);
        }
    }

    /* ── İlan kartı HTML ─────────────────────────────────────── */
    /* ── Inline SVG icon helpers (FA 6 Free) ─────────────────── */
    const _svgCrown = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512" style="width:8px;height:8px;fill:white;display:inline-block;vertical-align:middle;"><path d="M309 106c11.4-7 19-19.7 19-34 0-22.1-17.9-40-40-40s-40 17.9-40 40c0 14.4 7.6 27 19 34L209.7 220.6c-9.1 18.2-32.7 23.4-48.6 10.7L72 160c5-6.7 8-15 8-24 0-22.1-17.9-40-40-40S0 113.9 0 136s17.9 40 40 40l.7 0L86.4 427.4c5.5 30.4 32 52.6 63.6 52.6l276 0c31.6 0 58.1-22.2 63.6-52.6L535.3 176l.7 0c22.1 0 40-17.9 40-40s-17.9-40-40-40-40 17.9-40 40c0 9 3 17.3 8 24l-89.1 71.3c-15.9 12.7-39.5 7.5-48.6-10.7L309 106z"/></svg>';
    const _svgShield = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" style="width:8px;height:8px;fill:white;display:inline-block;vertical-align:middle;"><path d="M256 0c4.6 0 9.2 1 13.4 2.9L457.7 82.8c22 9.3 38.4 31 38.3 57.2-.5 99.2-41.3 280.7-213.6 363.2-16.7 8-36.1 8-52.8 0C57.3 420.7 16.5 239.2 16 140c-.1-26.2 16.3-47.9 38.3-57.2L242.7 2.9C246.8 1 251.4 0 256 0z"/></svg>';
    const _svgBolt = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512" style="width:8px;height:8px;fill:white;display:inline-block;vertical-align:middle;"><path d="M349.4 44.6c5.9-13.7 1.5-29.7-10.6-38.5s-28.6-8-39.9 1.8l-256 224c-10 8.8-13.6 22.9-8.9 35.3S50.7 288 64 288l111.5 0L98.6 467.4c-5.9 13.7-1.5 29.7 10.6 38.5s28.6 8 39.9-1.8l256-224c10-8.8 13.6-22.9 8.9-35.3s-16.6-20.7-30-20.7l-111.5 0L349.4 44.6z"/></svg>';
    const _svgFire = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512" style="width:8px;height:8px;fill:white;display:inline-block;vertical-align:middle;"><path d="M159.3 5.4c7.8-7.3 19.9-7.2 27.7 .1c27.6 25.9 53.5 53.8 67.8 84.7c11.6 25.3 17.5 52.8 17.7 80.6l-.1 2.5c11.7-7.5 23.9-13.4 36.7-17.9c4.9-1.7 10-2.8 15.1-3.2c3.2-.3 6.4 .1 9.4 1.2c7.7 2.8 13.7 9.1 15.6 17.1c4.8 19.4 5.2 39.8 .6 59.4c-3.3 13.9-9.6 27.2-18.5 38.8c18.5-.8 37.5 .2 56.1 3.4c3.4 .6 6.7 1.5 9.9 2.7c6.2 2.4 11 7.4 13.3 13.7c2.3 6.3 1.7 13.3-1.6 19.2c-9.7 17.2-22.9 32.2-38.7 44.3c15.6 5 30.4 12.4 43.8 22c4.6 3.3 8.6 7.3 11.7 11.8c6.1 8.9 7.4 20.1 3.3 30.1c-4.1 10-12.8 17.5-23.5 20c-58.7 14-123.4 8.9-178.7-14.7c-28.1-12.1-54.3-30.4-76.7-53.7c-22.3-23.3-40.8-51-52.9-81.8c-12.1-30.8-17.9-63.9-16.5-97.2l.1-2.2c-9.9 9.8-19.7 20.4-28.8 31.5C114.6 188.1 106.7 189 99 186.3c-7.7-2.6-13.6-9-15.5-17L73 128.9c-4.9-20.4-5.5-41.6-.7-62.2c4.8-20.6 14.6-39.5 28.4-55.4c7.7-8.8 19.8-9.4 27.7-1.1L159.3 5.4z"/></svg>';

    function _badgePill(bg, svg) {
        return `<span style="position:absolute;padding:2px 4px;border-radius:4px;pointer-events:none;z-index:2;background:${bg};">${svg}</span>`;
    }

    function cardHtml(l) {
        const img = firstImage(l);
        const price = fmtPrice(l.price);
        const imgHtml = img
            ? `<img src="${esc(img)}" alt="${esc(l.title)}" loading="lazy" onerror="this.style.display='none'">`
            : `<div class="listing-tile-placeholder"><svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg></div>`;
        const priceHtml = price ? `<div class="listing-tile-price">${esc(price)}</div>` : '';
        const sponsoredHtml = l.is_sponsored
            ? '<span style="position:absolute;top:6px;left:6px;background:rgba(0,0,0,.62);color:#fff;font-size:.68rem;font-weight:700;padding:2px 7px;border-radius:5px;pointer-events:none;z-index:1;">Sponsorlu</span>'
            : '';

        const isPro     = l.seller_is_premium === true;
        const badge     = l.seller_badge;
        const trending  = l.is_trending === true;
        const proBadge  = isPro ? `<span style="position:absolute;top:5px;right:5px;padding:2px 4px;border-radius:4px;pointer-events:none;z-index:2;background:linear-gradient(to right,#0891b2,#06b6d4);">${_svgCrown}</span>` : '';
        const sellerBadge = badge === 'trusted_seller'
            ? `<span style="position:absolute;top:${isPro ? 22 : 5}px;right:5px;padding:2px 4px;border-radius:4px;pointer-events:none;z-index:2;background:#16a34a;">${_svgShield}</span>`
            : badge === 'active_seller'
            ? `<span style="position:absolute;top:${isPro ? 22 : 5}px;right:5px;padding:2px 4px;border-radius:4px;pointer-events:none;z-index:2;background:#f59e0b;">${_svgBolt}</span>`
            : '';
        const trendBadge = trending ? `<span style="position:absolute;bottom:5px;right:5px;padding:2px 4px;border-radius:4px;pointer-events:none;z-index:2;background:rgba(234,88,12,.88);">${_svgFire}</span>` : '';

        return `<a class="listing-tile feed-card"
            href="/ilan/${l.id}"
            data-listing-id="${l.id}"
            data-campaign-id="${l.campaign_id || ''}"
            data-category="${esc(l.category || '')}"
            style="position:relative;">
            ${imgHtml}
            ${sponsoredHtml}
            ${proBadge}${sellerBadge}${trendBadge}
            ${priceHtml}
        </a>`;
    }

    /* ── Sinyal: skip / impression ────────────────────────────── */
    function observeCards(grid) {
        const cardObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                const el = entry.target;
                const lid = parseInt(el.dataset.listingId, 10);
                const cat = el.dataset.category || '';
                if (entry.isIntersecting) {
                    _timers.set(lid, { t: Date.now(), cat });
                } else {
                    const info = _timers.get(lid);
                    if (!info) return;
                    const elapsed = Date.now() - info.t;
                    _timers.delete(lid);
                    track(elapsed < 1500 ? 'listing_skip' : 'feed_impression',
                          { listing_id: lid, category: info.cat });
                }
            });
        }, { threshold: 0.5 });

        grid.querySelectorAll('.feed-card:not([data-obs])').forEach(c => {
            c.dataset.obs = '1';
            cardObserver.observe(c);
        });
    }

    /* ── Bir sayfa yükle ──────────────────────────────────────── */
    async function loadPage() {
        if (_loading || _exhausted) return;
        _loading = true;

        const sentinel = document.getElementById('feedSentinel');
        if (sentinel) sentinel.style.display = 'block';

        try {
            const items = await apiFetch(`/feed?page=${_page}&seed=${_seed}`);
            const grid = document.getElementById('personalizedGrid');
            if (!grid) return;

            if (!items || items.length === 0) {
                _exhausted = true;
                if (sentinel) sentinel.style.display = 'none';
                if (_page === 0) showEmpty();
                return;
            }

            const tmp = document.createElement('div');
            tmp.innerHTML = items.map(cardHtml).join('');
            while (tmp.firstChild) grid.appendChild(tmp.firstChild);

            observeCards(grid);

            _page++;
            if (items.length < 20) {
                _exhausted = true;
                if (sentinel) sentinel.style.display = 'none';
            }
        } catch (err) {
            console.error('[Kesfet] Feed yüklenemedi:', err);
            if (_page === 0) showEmpty();
            if (sentinel) sentinel.style.display = 'none';
        } finally {
            _loading = false;
        }
    }

    /* ── Boş durum ───────────────────────────────────────────── */
    function showEmpty() {
        const section = document.getElementById('personalizedFeedSection');
        if (!section || section.querySelector('.feed-empty')) return;
        const el = document.createElement('div');
        el.className = 'feed-empty empty-state';
        el.innerHTML = `
            <svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
            <p>Henüz gösterilecek ilan yok.</p>`;
        section.appendChild(el);
    }

    /* ── Sonsuz scroll ───────────────────────────────────────── */
    function setupInfiniteScroll() {
        const sentinel = document.getElementById('feedSentinel');
        if (!sentinel || _scrollObserver) return;
        _scrollObserver = new IntersectionObserver(
            (entries) => { if (entries[0].isIntersecting) loadPage(); },
            { rootMargin: '300px' }
        );
        _scrollObserver.observe(sentinel);
    }

    /* ── Sponsorlu ilan tıklama takibi ────────────────────── */
    function initAdClickTracking() {
        var grid = document.getElementById('personalizedGrid');
        if (!grid) return;
        grid.addEventListener('click', function (e) {
            var card = e.target.closest('[data-campaign-id]');
            if (!card || !card.dataset.campaignId) return;
            // Fire-and-forget — navigasyonu bloklamaz
            apiFetch('/ads/click/' + card.dataset.campaignId, { method: 'POST' }).catch(function () {});
        });
    }

    /* ── Başlat ──────────────────────────────────────────────── */
    function init() {
        // Auth.ready await edildikten sonra çağrıldığı için token garanti edilir.
        const isLoggedIn = typeof Auth !== 'undefined' && !!Auth.getToken();

        if (!isLoggedIn) {
            // Misafir: search.js her şeyi yönetir, bizim yapacak bir şeyimiz yok
            return;
        }

        // Giriş yapmış: kişiselleştirilmiş ilan feed'ini başlat
        const feedSection = document.getElementById('personalizedFeedSection');
        if (feedSection) feedSection.style.display = 'block';

        setupInfiniteScroll();
        loadPage();
        initAdClickTracking();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { Auth.ready.then(init); });
    } else {
        Auth.ready.then(init);
    }
})();
