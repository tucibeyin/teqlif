/**
 * search.js — kesfet.html için keşfet & arama mantığı
 *
 * Bağımlılıklar (sırayla yüklenmeli):
 *   main.js   → apiFetch
 *   auth.js   → Auth
 *   stream.js → Stream
 */

(function () {
    'use strict';

    /* ── DOM referansları ─────────────────────────────────────── */
    const searchInput      = document.getElementById('searchInput');
    const clearBtn         = document.getElementById('clearBtn');
    const exploreView      = document.getElementById('exploreView');
    const exploreLoading   = document.getElementById('exploreLoading');
    const streamsSection   = document.getElementById('streamsSection');
    const streamsScroll    = document.getElementById('streamsScroll');
    const listingsSection  = document.getElementById('listingsSection');
    const listingsGrid     = document.getElementById('listingsGrid');
    const exploreEmpty     = document.getElementById('exploreEmpty');

    const searchView           = document.getElementById('searchView');
    const searchLoading        = document.getElementById('searchLoading');
    const usersSection         = document.getElementById('usersSection');
    const usersList            = document.getElementById('usersList');
    const searchListingsSection = document.getElementById('searchListingsSection');
    const searchListingsGrid   = document.getElementById('searchListingsGrid');
    const searchStreamsSection  = document.getElementById('searchStreamsSection');
    const searchStreamsList    = document.getElementById('searchStreamsList');
    const searchEmpty          = document.getElementById('searchEmpty');

    /* ── Yardımcılar ──────────────────────────────────────────── */
    function esc(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function fmtPrice(price) {
        if (price == null) return '';
        const s = Math.round(Number(price)).toString();
        let result = '';
        for (let i = 0; i < s.length; i++) {
            if (i > 0 && (s.length - i) % 3 === 0) result += '.';
            result += s[i];
        }
        return result + ' ₺';
    }

    function firstImage(listing) {
        if (listing.image_urls && listing.image_urls.length > 0) return listing.image_urls[0];
        return listing.image_url || null;
    }

    function userInitial(user) {
        const name = user.full_name || user.username || '?';
        return name[0].toUpperCase();
    }

    /* ── Görünüm geçişleri ────────────────────────────────────── */
    function showExplore() {
        exploreView.style.display = 'block';
        searchView.style.display = 'none';
    }

    function showSearch() {
        exploreView.style.display = 'none';
        searchView.style.display = 'block';
    }

    /* ── Keşfet verisini yükle ────────────────────────────────── */
    async function loadExplore() {
        exploreLoading.style.display = 'block';
        streamsSection.style.display = 'none';
        listingsSection.style.display = 'none';
        exploreEmpty.style.display = 'none';

        try {
            const data = await apiFetch('/search/explore');
            renderExplore(data);
        } catch (_) {
            exploreLoading.style.display = 'none';
            exploreEmpty.style.display = 'block';
        }
    }

    function renderExplore(data) {
        exploreLoading.style.display = 'none';
        const { listings = [], streams = [] } = data;

        if (streams.length > 0) {
            streamsScroll.innerHTML = streams.map(streamCardHtml).join('');
            streamsSection.style.display = 'block';
        }

        if (listings.length > 0) {
            listingsGrid.innerHTML = listings.map(listingTileHtml).join('');
            listingsSection.style.display = 'block';
        }

        if (streams.length === 0 && listings.length === 0) {
            exploreEmpty.style.display = 'block';
        }
    }

    /* ── Toast bildirimi ──────────────────────────────────────── */
    function showToast(msg) {
        let toast = document.getElementById('kesfetToast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'kesfetToast';
            toast.style.cssText = 'position:fixed;bottom:1.5rem;left:50%;transform:translateX(-50%);background:#1a1a1a;color:#fff;padding:0.65rem 1.25rem;border-radius:10px;font-size:0.88rem;font-weight:500;z-index:9999;opacity:0;transition:opacity 0.2s;pointer-events:none;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.2);';
            document.body.appendChild(toast);
        }
        toast.textContent = msg;
        toast.style.opacity = '1';
        clearTimeout(toast._timer);
        toast._timer = setTimeout(() => { toast.style.opacity = '0'; }, 2500);
    }

    /* ── Arama ────────────────────────────────────────────────── */
    let _debounce = null;

    function onInput() {
        const q = searchInput.value.trim();

        if (q && !Auth.getToken()) {
            searchInput.value = '';
            clearBtn.style.display = 'none';
            showToast('Arama yapmak için giriş yapmalısınız');
            return;
        }

        clearBtn.style.display = q ? 'block' : 'none';

        if (!q) {
            showExplore();
            return;
        }

        showSearch();
        clearTimeout(_debounce);
        _debounce = setTimeout(() => doSearch(q), 400);
    }

    async function doSearch(q) {
        searchLoading.style.display = 'block';
        usersSection.style.display = 'none';
        searchListingsSection.style.display = 'none';
        searchStreamsSection.style.display = 'none';
        searchEmpty.style.display = 'none';

        try {
            const data = await apiFetch('/search/all?q=' + encodeURIComponent(q));
            renderSearchResults(data);
        } catch (_) {
            searchLoading.style.display = 'none';
            searchEmpty.style.display = 'block';
        }
    }

    function renderSearchResults(data) {
        searchLoading.style.display = 'none';
        const { users = [], listings = [], streams = [] } = data;

        if (users.length > 0) {
            usersList.innerHTML = users.map(userRowHtml).join('');
            usersSection.style.display = 'block';
        }

        if (listings.length > 0) {
            searchListingsGrid.innerHTML = listings.map(listingTileHtml).join('');
            searchListingsSection.style.display = 'block';
        }

        if (streams.length > 0) {
            searchStreamsList.innerHTML = streams.map(streamRowHtml).join('');
            searchStreamsSection.style.display = 'block';
        }

        if (users.length === 0 && listings.length === 0 && streams.length === 0) {
            searchEmpty.style.display = 'block';
        }
    }

    /* ── HTML şablonları ──────────────────────────────────────── */

    // Yatay kaydırma stream kartı (keşfet varsayılan)
    function streamCardHtml(s) {
        const hasThumbnail = s.thumbnail_url && s.thumbnail_url.trim();
        const thumbHtml = hasThumbnail
            ? `<img src="${esc(s.thumbnail_url)}" alt="${esc(s.title)}" onerror="this.parentElement.innerHTML='${gradientHtml()}';">`
            : gradientHtml();

        return `
        <div class="stream-card" onclick="joinStream(${s.id})">
            ${thumbHtml}
            <div class="stream-card-badge">CANLI</div>
            <div class="stream-card-info">
                <div class="stream-card-title">${esc(s.title)}</div>
                <div class="stream-card-host">@${esc(s.host.username)}</div>
            </div>
        </div>`;
    }

    // İlan tile (hem keşfet hem arama sonuçları için)
    function listingTileHtml(l) {
        const img = firstImage(l);
        const price = fmtPrice(l.price);
        const imgHtml = img
            ? `<img src="${esc(img)}" alt="${esc(l.title)}" loading="lazy" onerror="this.style.display='none'">`
            : `<div class="listing-tile-placeholder"><svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg></div>`;
        const priceHtml = price ? `<div class="listing-tile-price">${esc(price)}</div>` : '';

        return `
        <a class="listing-tile" href="/ilan.html?id=${l.id}">
            ${imgHtml}
            ${priceHtml}
        </a>`;
    }

    // Kullanıcı satırı (arama sonuçları)
    function userRowHtml(u) {
        const name = esc(u.full_name || u.username || '?');
        const handle = esc(u.username || '');
        const initial = userInitial(u);
        const avatarHtml = u.profile_image_url
            ? `<div class="user-avatar"><img src="${esc(u.profile_image_url)}" alt="${name}" onerror="this.parentElement.textContent='${initial}'"></div>`
            : `<div class="user-avatar">${initial}</div>`;

        return `
        <a class="user-row" href="/profil.html?u=${handle}">
            ${avatarHtml}
            <div>
                <div class="user-info-name">${name}</div>
                <div class="user-info-handle">@${handle}</div>
            </div>
        </a>`;
    }

    // Yatay stream satırı (arama sonuçları)
    function streamRowHtml(s) {
        const hasThumbnail = s.thumbnail_url && s.thumbnail_url.trim();
        const thumbHtml = hasThumbnail
            ? `<img src="${esc(s.thumbnail_url)}" alt="${esc(s.title)}" style="width:100%;height:100%;object-fit:cover;">`
            : `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.5)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>`;

        return `
        <div class="stream-row" onclick="joinStream(${s.id})">
            <div class="stream-row-thumb">${thumbHtml}</div>
            <div style="flex:1;min-width:0;">
                <div class="stream-row-title">${esc(s.title)}</div>
                <div class="stream-row-host">@${esc(s.host.username)}</div>
            </div>
            <span class="stream-row-badge">CANLI</span>
        </div>`;
    }

    // Gradyan arka plan (thumbnail olmayan streamler için)
    function gradientHtml() {
        return `<div class="stream-card-gradient"><svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg></div>`;
    }

    /* ── Yayına katıl ─────────────────────────────────────────── */
    window.joinStream = async function (id) {
        if (!Auth.getToken()) {
            showToast('Yayına katılmak için giriş yapmalısınız');
            return;
        }
        try {
            await Stream.joinStream(id);
            window.location.href = `/yayin.html?id=${id}`;
        } catch (err) {
            showToast(err.detail || 'Yayına katılınamadı');
        }
    };

    /* ── Event dinleyicileri ──────────────────────────────────── */
    searchInput.addEventListener('input', onInput);

    clearBtn.addEventListener('click', function () {
        searchInput.value = '';
        clearBtn.style.display = 'none';
        searchInput.focus();
        showExplore();
    });

    /* ── Sayfa yüklendiğinde (script body sonunda, DOM hazır) ─── */
    loadExplore();

})();
