/**
 * kesfet-page.js — Kişiselleştirilmiş feed (Sana Özel sekmesi)
 *
 * Bağımlılıklar:
 *   main.js → apiFetch
 *   auth.js → Auth
 *   feed-tracker.js → FeedTracker
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
    let _observer = null;
    let _trackerObserver = null;
    let _activeTab = null;  // 'personalized' | 'all'

    const GRID_ID     = 'personalizedGrid';
    const SECTION_ID  = 'personalizedFeedSection';
    const SENTINEL_ID = 'feedSentinel';
    const TAB_PERSONAL_ID = 'tabPersonalized';
    const TAB_ALL_ID      = 'tabAll';

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

    /* ── İlan kartı HTML ─────────────────────────────────────── */
    function feedCardHtml(l) {
        const img = firstImage(l);
        const price = fmtPrice(l.price);
        const imgHtml = img
            ? `<img src="${esc(img)}" alt="${esc(l.title)}" loading="lazy" onerror="this.style.display='none'">`
            : `<div class="listing-tile-placeholder"><svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg></div>`;
        const priceHtml = price ? `<div class="listing-tile-price">${esc(price)}</div>` : '';

        return `<a class="listing-tile feed-card"
            href="/ilan/${l.id}"
            data-listing-id="${l.id}"
            data-category="${esc(l.category || '')}">
            ${imgHtml}
            ${priceHtml}
        </a>`;
    }

    /* ── Bir sayfa yükle ──────────────────────────────────────── */
    async function loadPage() {
        if (_loading || _exhausted) return;
        _loading = true;

        const sentinel = document.getElementById(SENTINEL_ID);
        if (sentinel) sentinel.style.display = 'block';

        try {
            const items = await apiFetch(`/feed?page=${_page}&seed=${_seed}`);

            const grid = document.getElementById(GRID_ID);
            if (!grid) return;

            if (!items || items.length === 0) {
                _exhausted = true;
                if (sentinel) sentinel.style.display = 'none';
                if (_page === 0) showEmpty();
                return;
            }

            const fragment = document.createDocumentFragment();
            items.forEach(l => {
                const tmp = document.createElement('div');
                tmp.innerHTML = feedCardHtml(l);
                const card = tmp.firstElementChild;
                fragment.appendChild(card);
            });
            grid.appendChild(fragment);

            // FeedTracker: yeni kartları gözlemle
            if (window.FeedTracker) {
                if (_trackerObserver) {
                    grid.querySelectorAll('.feed-card:not([data-observed])').forEach(card => {
                        card.dataset.observed = '1';
                        _trackerObserver.observe(card);
                    });
                }
            }

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
        const section = document.getElementById(SECTION_ID);
        if (!section) return;
        const existing = section.querySelector('.feed-empty');
        if (existing) return;
        const empty = document.createElement('div');
        empty.className = 'feed-empty empty-state';
        empty.innerHTML = `
            <svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
            <p>Henüz gösterilecek ilan yok.<br>İlanları beğen ve favorile, sana özel ilanlar burada görünür.</p>`;
        section.appendChild(empty);
    }

    /* ── Sonsuz scroll kurulumu ──────────────────────────────── */
    function setupInfiniteScroll() {
        const sentinel = document.getElementById(SENTINEL_ID);
        if (!sentinel || _observer) return;

        _observer = new IntersectionObserver((entries) => {
            if (entries[0].isIntersecting) loadPage();
        }, { rootMargin: '300px' });

        _observer.observe(sentinel);
    }

    /* ── FeedTracker IntersectionObserver ────────────────────── */
    function setupTracker() {
        if (!window.FeedTracker) return;
        const grid = document.getElementById(GRID_ID);
        if (!grid) return;

        _trackerObserver = new IntersectionObserver((entries) => {
            const SKIP_MS = 1500;
            const _timers = setupTracker._timers || (setupTracker._timers = new Map());

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
                    const eventType = elapsed < SKIP_MS ? 'listing_skip' : 'feed_impression';
                    if (typeof window.teqlifTrackEvent === 'function') {
                        window.teqlifTrackEvent(eventType, { listing_id: lid, category: cat });
                    }
                }
            });
        }, { threshold: 0.5 });
    }

    /* ── Sekme geçişleri ─────────────────────────────────────── */
    function switchTab(tab) {
        if (_activeTab === tab) return;
        _activeTab = tab;

        const tabPersonal = document.getElementById(TAB_PERSONAL_ID);
        const tabAll      = document.getElementById(TAB_ALL_ID);
        const feedSection = document.getElementById(SECTION_ID);
        const listSection = document.getElementById('listingsSection');

        if (tab === 'personalized') {
            tabPersonal?.classList.add('feed-tab-active');
            tabAll?.classList.remove('feed-tab-active');
            if (feedSection) feedSection.style.display = 'block';
            if (listSection) listSection.style.display = 'none';

            // İlk yükleme
            const grid = document.getElementById(GRID_ID);
            if (grid && grid.children.length === 0 && !_exhausted) {
                setupTracker();
                setupInfiniteScroll();
                loadPage();
            }
        } else {
            tabPersonal?.classList.remove('feed-tab-active');
            tabAll?.classList.add('feed-tab-active');
            if (feedSection) feedSection.style.display = 'none';
            if (listSection) listSection.style.display = 'block';
        }
    }

    /* ── Sekme başlatma ──────────────────────────────────────── */
    function initTabs() {
        const tabPersonal = document.getElementById(TAB_PERSONAL_ID);
        const tabAll      = document.getElementById(TAB_ALL_ID);
        const feedTabs    = document.getElementById('feedTabs');

        if (!feedTabs) return;

        tabPersonal?.addEventListener('click', () => switchTab('personalized'));
        tabAll?.addEventListener('click', () => switchTab('all'));

        // Giriş yapmış kullanıcıya "Sana Özel" varsayılan
        const isLoggedIn = !!Auth.getToken();
        if (isLoggedIn) {
            feedTabs.style.display = 'flex';
            switchTab('personalized');
        } else {
            // Misafir: tab'ları gösterme, sadece "Tümü" (mevcut davranış)
            feedTabs.style.display = 'none';
            _activeTab = 'all';
        }
    }

    /* ── Sayfa yüklendiğinde ─────────────────────────────────── */
    // search.js'deki loadExplore() zaten streams + listingsGrid'i doldurur.
    // Biz sadece tab mantığını ekliyoruz.
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initTabs);
    } else {
        initTabs();
    }

    // Auth.onReady yoksa küçük bir gecikmeyle bekle
    if (typeof Auth !== 'undefined' && typeof Auth.onReady === 'function') {
        Auth.onReady(initTabs);
    } else {
        setTimeout(initTabs, 150);
    }

})();
