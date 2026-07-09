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
        return `<a class="listing-tile feed-card"
            href="/ilan/${l.id}"
            data-listing-id="${l.id}"
            data-campaign-id="${l.campaign_id || ''}"
            data-category="${esc(l.category || '')}"
            style="position:relative;">
            ${imgHtml}
            ${sponsoredHtml}
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
