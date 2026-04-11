    const listingId = parseInt(location.pathname.split('/').pop(), 10);
    let _urls = [];
    let _cur = 0;
    let _isFavorited = false;
    let _isActive = true;
    let _isLiked = false;
    let _likesCount = 0;

    /* ── Helpers ── */
    function fmt(p) {
        if (p == null) return 'Fiyat belirtilmemiş';
        return '₺ ' + Number(p).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
    }

    function timeAgo(iso) {
        const diff = (Date.now() - new Date(iso)) / 1000;
        if (diff < 60) return 'Az önce';
        if (diff < 3600) return Math.floor(diff / 60) + ' dk önce';
        if (diff < 86400) return Math.floor(diff / 3600) + ' sa önce';
        if (diff < 2592000) return Math.floor(diff / 86400) + ' gün önce';
        return new Date(iso).toLocaleDateString('tr-TR');
    }

    function esc(s) {
        return String(s ?? '')
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    const CAT = {
        elektronik: '📱 Elektronik', vasita: '🚗 Vasıta', emlak: '🏠 Emlak',
        giyim: '👗 Giyim', spor: '⚽ Spor', kitap: '📚 Kitap & Müzik',
        ev: '🛋 Ev & Bahçe', diger: '📦 Diğer',
    };

    /* ── Gallery ── */
    function goTo(idx) {
        _cur = (idx + _urls.length) % _urls.length;
        document.querySelectorAll('.gallery-main img').forEach((img, i) => {
            img.classList.toggle('active', i === _cur);
        });
        document.querySelectorAll('.gallery-thumbs img').forEach((img, i) => {
            img.classList.toggle('active', i === _cur);
            if (i === _cur) img.scrollIntoView({ inline: 'nearest', behavior: 'smooth' });
        });
        const el = document.getElementById('galleryCounter');
        if (el) el.textContent = `${_cur + 1} / ${_urls.length}`;
    }

    /* ── Lightbox ── */
    function openLb(idx) {
        _cur = idx;
        document.getElementById('lightbox').classList.add('open');
        lbRefresh();
        document.addEventListener('keydown', lbKey);
    }

    function closeLb() {
        document.getElementById('lightbox').classList.remove('open');
        document.removeEventListener('keydown', lbKey);
    }

    function lbRefresh() {
        document.getElementById('lbImg').src = _urls[_cur];
        document.getElementById('lbCounter').textContent = `${_cur + 1} / ${_urls.length}`;
    }

    function lbNav(dir) {
        _cur = (_cur + dir + _urls.length) % _urls.length;
        lbRefresh();
        goTo(_cur);
    }

    function lbKey(e) {
        if (e.key === 'ArrowLeft') lbNav(-1);
        if (e.key === 'ArrowRight') lbNav(1);
        if (e.key === 'Escape') closeLb();
    }

    function lbClickOutside(e) {
        if (e.target === document.getElementById('lightbox')) closeLb();
    }

    /* ── Build gallery HTML ── */
    function buildGallery(urls) {
        if (!urls.length) {
            return `<div class="gallery-main" style="cursor:default"><div class="no-photo">📷</div></div>`;
        }
        const imgs = urls.map((u, i) =>
            `<img src="${u}" class="${i === 0 ? 'active' : ''}" alt="Fotoğraf ${i + 1}" loading="lazy">`
        ).join('');

        const arrows = urls.length > 1 ? `
            <button class="gallery-arrow prev" id="galleryPrev">‹</button>
            <button class="gallery-arrow next" id="galleryNext">›</button>` : '';

        const counter = urls.length > 1
            ? `<div class="gallery-counter" id="galleryCounter">1 / ${urls.length}</div>` : '';

        const thumbs = urls.length > 1 ? `
            <div class="gallery-thumbs">
                ${urls.map((u, i) =>
            `<img src="${u}" class="${i === 0 ? 'active' : ''}" data-thumb-idx="${i}" alt="">`
        ).join('')}
            </div>` : '';

        return `
            <div class="gallery-main" id="galleryMain">
                ${imgs}${arrows}${counter}
            </div>
            ${thumbs}`;
    }

    /* ── Skeleton ── */
    function showSkeleton() {
        document.getElementById('content').innerHTML = `
            <div class="detail-grid">
                <div>
                    <div class="card">
                        <div class="skeleton" style="aspect-ratio:4/3;border-radius:0"></div>
                        <div class="detail-body">
                            <div class="skeleton" style="height:14px;width:30%;margin-bottom:10px"></div>
                            <div class="skeleton" style="height:26px;width:70%;margin-bottom:14px"></div>
                            <div class="skeleton" style="height:16px;width:50%;margin-bottom:10px"></div>
                            <div class="skeleton" style="height:14px;margin-bottom:8px"></div>
                            <div class="skeleton" style="height:14px;width:80%;margin-bottom:8px"></div>
                            <div class="skeleton" style="height:14px;width:60%"></div>
                        </div>
                    </div>
                </div>
                <div style="display:flex;flex-direction:column;gap:1rem">
                    <div class="price-card">
                        <div class="skeleton" style="height:38px;width:60%;margin-bottom:8px"></div>
                        <div class="skeleton" style="height:44px;margin-bottom:8px"></div>
                        <div class="skeleton" style="height:40px"></div>
                    </div>
                </div>
            </div>`;
    }

    /* ── Main load ── */
    async function load() {
        showSkeleton();
        try {
            const data = await apiFetch(`/listings/${listingId}`);
            _urls = (data.image_urls && data.image_urls.length > 0)
                ? data.image_urls
                : data.image_url ? [data.image_url] : [];
            _cur = 0;

            document.title = `${data.title} — teqlif`;

            // ── Dynamic SEO meta tags ──
            const _ogImg = (data.image_urls && data.image_urls[0])
                ? `https://teqlif.com${data.image_urls[0]}`
                : (data.image_url ? `https://teqlif.com${data.image_url}` : 'https://teqlif.com/static/icons/icon.svg');
            const _ogDesc = data.description
                ? data.description.slice(0, 160)
                : `${data.title} — teqlif'te satılık ilan`;
            const _canonUrl = `https://teqlif.com/ilan/${listingId}`;
            const _setMeta = (prop, val, attr = 'property') => {
                let el = document.querySelector(`meta[${attr}="${prop}"]`);
                if (!el) { el = document.createElement('meta'); el.setAttribute(attr, prop); document.head.appendChild(el); }
                el.setAttribute('content', val);
            };
            let _canon = document.querySelector('link[rel="canonical"]');
            if (!_canon) { _canon = document.createElement('link'); _canon.rel = 'canonical'; document.head.appendChild(_canon); }
            _canon.href = _canonUrl;
            _setMeta('description', _ogDesc, 'name');
            _setMeta('og:url', _canonUrl);
            _setMeta('og:title', document.title);
            _setMeta('og:description', _ogDesc);
            _setMeta('og:image', _ogImg);
            _setMeta('twitter:title', document.title, 'name');
            _setMeta('twitter:description', _ogDesc, 'name');
            _setMeta('twitter:image', _ogImg, 'name');
            // JSON-LD Product schema
            const _ldEl = document.getElementById('ld-json') || (() => {
                const s = document.createElement('script');
                s.id = 'ld-json'; s.type = 'application/ld+json';
                document.head.appendChild(s); return s;
            })();
            _ldEl.textContent = JSON.stringify({
                '@context': 'https://schema.org',
                '@type': 'Product',
                'name': data.title,
                'description': data.description || data.title,
                'image': _ogImg,
                'url': _canonUrl,
                'offers': {
                    '@type': 'Offer',
                    'price': data.price ?? 0,
                    'priceCurrency': 'TRY',
                    'availability': 'https://schema.org/InStock',
                    'seller': {
                        '@type': 'Person',
                        'name': data.user.full_name || data.user.username
                    }
                }
            });

            const catLabel = CAT[data.category] || data.category || '';
            const initials = (data.user.full_name || data.user.username || '?')[0].toUpperCase();
            const me = Auth.getUser();
            const isLoggedIn = !!me;
            const isOwner = me && me.id === data.user.id;
            _isActive    = data.is_active !== false;
            _isLiked     = data.is_liked    ?? false;
            _likesCount  = data.likes_count ?? 0;

            // Favori durumunu kontrol et (non-owner + logged in)
            if (isLoggedIn && !isOwner) {
                try {
                    const favResp = await apiFetch(`/favorites/${listingId}`);
                    _isFavorited = favResp.is_favorited || false;
                } catch (_) { }
            }

            document.getElementById('content').innerHTML = `
                <div class="detail-grid">

                    <!-- LEFT -->
                    <div style="display:flex;flex-direction:column;gap:1rem">
                        <div class="card">
                            ${buildGallery(_urls)}
                            <div class="detail-body">
                                <div class="detail-meta">
                                    ${catLabel ? `<span class="cat-badge">${catLabel}</span>` : ''}
                                    <span class="ilan-date">${timeAgo(data.created_at)}</span>
                                    ${_likesCount > 0 ? `<span style="font-size:.8rem;color:#e53e3e;">♥ ${_likesCount}</span>` : ''}
                                </div>
                                <h1 class="detail-title">${esc(data.title)}</h1>
                                ${data.location ? `
                                <div class="detail-location">
                                    <span>📍</span><span>${esc(data.location)}</span>
                                </div>` : ''}
                                ${data.description ? `
                                <hr class="divider">
                                <div class="sec-label">Açıklama</div>
                                <div class="detail-desc">${esc(data.description)}</div>` : ''}
                                ${!isOwner && isLoggedIn ? `
                                <div style="margin-top:1rem;text-align:right;">
                                    <button class="btn-report" id="reportBtn">
                                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg>
                                        Şikayet Et
                                    </button>
                                </div>` : ''}
                            </div>
                        </div>
                    </div>

                    <!-- RIGHT -->
                    <div style="display:flex;flex-direction:column;gap:1rem">
                        <div class="price-card">
                            <div class="price-tag">${fmt(data.price)}</div>
                            <div class="price-note">KDV dahil</div>
                            ${isOwner
                    ? `<button class="btn-toggle ${_isActive ? '' : 'passive'}" id="toggleBtn">
                                       ${_isActive ? '✓ Aktif — Pasife Al' : '✕ Pasif — Aktif Yap'}
                                   </button>
                                   <button class="btn-delete" id="deleteBtn">İlanı Sil</button>
                                   <div style="display:flex;align-items:center;gap:6px;padding:.5rem 0;color:#e53e3e;font-size:.9rem;">
                                       <svg width="15" height="15" viewBox="0 0 24 24" fill="#e53e3e" stroke="#e53e3e" stroke-width="2"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
                                       <span>${_likesCount} beğeni</span>
                                   </div>`
                    : isLoggedIn
                        ? `<button class="btn-fav ${_isFavorited ? 'active' : ''}" id="favBtn">
                                           ${_isFavorited ? '❤ Favorilerimde' : '♡ Favorilere Ekle'}
                                       </button>
                                       <button id="likeBtn" style="display:flex;align-items:center;justify-content:center;gap:6px;width:100%;padding:.6rem 1rem;border-radius:8px;border:1.5px solid ${_isLiked ? '#e53e3e' : '#e5e7eb'};background:${_isLiked ? '#fef2f2' : 'transparent'};color:${_isLiked ? '#e53e3e' : '#6b7280'};font-size:.9rem;font-weight:600;cursor:pointer;transition:all .15s;">
                                           <svg id="likeIcon" width="16" height="16" viewBox="0 0 24 24" fill="${_isLiked ? '#e53e3e' : 'none'}" stroke="${_isLiked ? '#e53e3e' : 'currentColor'}" stroke-width="2"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
                                           <span id="likeLabel">${_isLiked ? 'Beğenildi' : 'Beğen'}</span>
                                           ${_likesCount > 0 ? `<span id="likeCnt" style="font-size:.8rem;opacity:.75;">(${_likesCount})</span>` : `<span id="likeCnt" style="font-size:.8rem;opacity:.75;"></span>`}
                                       </button>
                                       <a href="/mesajlar?to_id=${data.user.id}&to_name=${encodeURIComponent(data.user.full_name || data.user.username)}&to_handle=${encodeURIComponent(data.user.username)}" class="btn-contact">Satıcıya Mesaj Gönder</a>`
                        : `<a href="/giris.html?next=/ilan/${listingId}" style="display:flex;align-items:center;justify-content:center;gap:6px;width:100%;padding:.6rem 1rem;border-radius:8px;border:1.5px solid #e5e7eb;background:transparent;color:#6b7280;font-size:.9rem;font-weight:600;cursor:pointer;text-decoration:none;margin-bottom:.5rem;">
                                           <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
                                           Beğen${_likesCount > 0 ? ` (${_likesCount})` : ''}
                                       </a>
                                       <a href="/giris.html?next=/ilan/${listingId}" class="btn-contact">Satıcıya Mesaj Gönder</a>`
                }
                            ${!isOwner ? `<a href="/profil/${esc(data.user.username)}" class="btn-msg">Profili Gör</a>` : ''}
                        </div>

                        <div class="seller-block">
                            <div class="sec-label" style="margin-bottom:.75rem">Satıcı</div>
                            <a href="${isOwner ? '/hesabim.html' : '/profil/' + esc(data.user.username)}" class="seller-row">
                                <div class="seller-avatar">${esc(initials)}</div>
                                <div>
                                    <div class="seller-name">${esc(data.user.full_name || data.user.username)}</div>
                                    <div class="seller-username">@${esc(data.user.username)}</div>
                                </div>
                                <span class="seller-goto">${isOwner ? 'Hesabım →' : 'Profile Git →'}</span>
                            </a>
                        </div>

                        <div class="offer-card">
                            <div class="sec-label" style="margin-bottom:.75rem">Teklif Geçmişi</div>
                            ${!isOwner && isLoggedIn ? `
                            <div class="offer-form-row">
                                <input type="text" inputmode="numeric" class="offer-input" id="offerInput" placeholder="₺ Teklifinizi girin" autocomplete="off">
                                <button class="btn-offer" id="offerBtn">Teklif Ver</button>
                            </div>
                            <div class="offer-form-error" id="offerError"></div>
                            ` : !isOwner && !isLoggedIn ? `
                            <p style="font-size:.85rem;color:#6b7280;margin:0 0 .85rem;">
                                Teklif vermek için <a href="/giris.html?next=/ilan/${listingId}" style="color:var(--primary,#06b6d4);font-weight:600;">giriş yapın</a>.
                            </p>
                            ` : ''}
                            <div class="offer-list" id="offerList">
                                <div class="offer-empty">Yükleniyor...</div>
                            </div>
                        </div>
                    </div>

                </div>`;

            // ── Wire up dynamic buttons after innerHTML (CSP: no inline onclick) ──
            var galleryMainEl = document.getElementById('galleryMain');
            if (galleryMainEl) {
                galleryMainEl.addEventListener('click', function () { openLb(_cur); });
                galleryMainEl.addEventListener('dblclick', function (e) { e.stopPropagation(); toggleListingLike(); });
            }
            var galleryPrevEl = document.getElementById('galleryPrev');
            if (galleryPrevEl) galleryPrevEl.addEventListener('click', function (e) { e.stopPropagation(); goTo(_cur - 1); });
            var galleryNextEl = document.getElementById('galleryNext');
            if (galleryNextEl) galleryNextEl.addEventListener('click', function (e) { e.stopPropagation(); goTo(_cur + 1); });
            var galleryThumbsEl = document.querySelector('.gallery-thumbs');
            if (galleryThumbsEl) galleryThumbsEl.addEventListener('click', function (e) {
                var img = e.target.closest('[data-thumb-idx]');
                if (img) goTo(Number(img.dataset.thumbIdx));
            });
            var reportBtnEl = document.getElementById('reportBtn');
            if (reportBtnEl) reportBtnEl.addEventListener('click', openReportModal);
            var toggleBtnEl = document.getElementById('toggleBtn');
            if (toggleBtnEl) toggleBtnEl.addEventListener('click', toggleActive);
            var deleteBtnEl = document.getElementById('deleteBtn');
            if (deleteBtnEl) deleteBtnEl.addEventListener('click', openDeleteModal);
            var favBtnEl = document.getElementById('favBtn');
            if (favBtnEl) favBtnEl.addEventListener('click', toggleFav);
            var likeBtnEl = document.getElementById('likeBtn');
            if (likeBtnEl) likeBtnEl.addEventListener('click', toggleListingLike);
            var offerBtnEl = document.getElementById('offerBtn');
            if (offerBtnEl) offerBtnEl.addEventListener('click', submitOffer);
            var offerInputEl = document.getElementById('offerInput');
            if (offerInputEl) offerInputEl.addEventListener('input', function () {
                var digits = this.value.replace(/\D/g, '');
                this.value = digits ? Number(digits).toLocaleString('tr-TR') : '';
            });

            loadOffers();

        } catch (e) {
            console.error('[İlan] Yüklenemedi:', e);
            if (window.Sentry) Sentry.captureException(e);
            document.getElementById('content').innerHTML = `
                <div class="error-box">
                    <h2>İlan bulunamadı</h2>
                    <p><a href="/">Ana sayfaya dön</a></p>
                </div>`;
        }
    }

    /* ── Teklif Ver / Geçmişi ── */
    async function loadOffers() {
        const list = document.getElementById('offerList');
        if (!list) return;
        try {
            const offers = await apiFetch(`/listings/${listingId}/offers`);
            if (!offers.length) {
                list.innerHTML = '<div class="offer-empty">Henüz teklif yok.</div>';
                return;
            }
            list.innerHTML = offers.map(o => `
                <div class="offer-row">
                    <span class="offer-amount">${fmt(o.amount)}</span>
                    <div class="offer-meta">
                        <span class="offer-user"><a href="/profil/${esc(o.username)}">@${esc(o.username)}</a></span>
                        <span class="offer-date">${timeAgo(o.created_at)}</span>
                    </div>
                </div>
            `).join('');
        } catch (e) {
            console.error('[Offers] Teklif geçmişi yüklenemedi:', e);
            if (window.Sentry) Sentry.captureException(e);
            if (list) list.innerHTML = '<div class="offer-empty">Teklifler yüklenemedi.</div>';
        }
    }

    async function submitOffer() {
        const input = document.getElementById('offerInput');
        const errEl = document.getElementById('offerError');
        const btn = document.getElementById('offerBtn');
        if (!input || !errEl || !btn) return;

        const amount = parseFloat(input.value.replace(/\./g, '').replace(',', '.'));
        errEl.style.display = 'none';

        if (!amount || amount <= 0) {
            errEl.textContent = 'Geçerli bir teklif miktarı girin.';
            errEl.style.display = 'block';
            return;
        }

        btn.disabled = true;
        try {
            await apiFetch(`/listings/${listingId}/offers`, {
                method: 'POST',
                body: JSON.stringify({ amount }),
            });
            input.value = '';
            await loadOffers();
        } catch (e) {
            console.error('[Offers] Teklif gönderilemedi:', e);
            if (window.Sentry) Sentry.captureException(e);
            errEl.textContent = e?.error?.message || e?.detail || 'Teklif gönderilemedi.';
            errEl.style.display = 'block';
        } finally {
            btn.disabled = false;
        }
    }

    /* ── Şikayet ── */
    function openReportModal() {
        document.getElementById('reportModal').classList.add('open');
    }
    function closeReportModal() {
        document.getElementById('reportModal').classList.remove('open');
        document.getElementById('reportReason').value = '';
        document.getElementById('reportNote').value = '';
        document.getElementById('reportMsg').style.display = 'none';
    }

    /* ── Favori ── */
    async function toggleFav() {
        const btn = document.getElementById('favBtn');
        if (!btn) return;
        btn.disabled = true;
        try {
            if (_isFavorited) {
                await apiFetch(`/favorites/${listingId}`, { method: 'DELETE' });
                _isFavorited = false;
                btn.className = 'btn-fav';
                btn.textContent = '♡ Favorilere Ekle';
            } else {
                await apiFetch(`/favorites/${listingId}`, { method: 'POST' });
                _isFavorited = true;
                btn.className = 'btn-fav active';
                btn.textContent = '❤ Favorilerimde';
            }
        } catch (_) { }
        btn.disabled = false;
    }

    /* ── İlan Beğeni ── */
    async function toggleListingLike() {
        if (!Auth.getToken()) return;
        const prevLiked = _isLiked;
        const prevCount = _likesCount;

        // Optimistic update
        _isLiked    = !_isLiked;
        _likesCount += _isLiked ? 1 : -1;
        _applyListingLikeUI();
        if (_isLiked) _triggerListingHeart();

        try {
            const result = await apiFetch(`/listings/${listingId}/like`, { method: 'POST' });
            _isLiked    = result.is_liked    ?? _isLiked;
            _likesCount = result.likes_count ?? _likesCount;
            _applyListingLikeUI();
        } catch (_) {
            _isLiked    = prevLiked;
            _likesCount = prevCount;
            _applyListingLikeUI();
        }
    }

    function _applyListingLikeUI() {
        const btn   = document.getElementById('likeBtn');
        const icon  = document.getElementById('likeIcon');
        const label = document.getElementById('likeLabel');
        const cnt   = document.getElementById('likeCnt');
        if (!btn) return;
        btn.style.borderColor  = _isLiked ? '#e53e3e' : '#e5e7eb';
        btn.style.background   = _isLiked ? '#fef2f2' : 'transparent';
        btn.style.color        = _isLiked ? '#e53e3e' : '#6b7280';
        if (icon)  { icon.setAttribute('fill', _isLiked ? '#e53e3e' : 'none'); icon.setAttribute('stroke', _isLiked ? '#e53e3e' : 'currentColor'); }
        if (label) label.textContent = _isLiked ? 'Beğenildi' : 'Beğen';
        if (cnt)   cnt.textContent   = _likesCount > 0 ? `(${_likesCount})` : '';
    }

    function _triggerListingHeart() {
        const gallery = document.querySelector('.gallery-main');
        if (!gallery) return;
        const heart = document.createElement('div');
        heart.className = 'floating-heart';
        const driftX = (Math.random() * 40 - 20) | 0;
        heart.style.setProperty('--hx', `${driftX}px`);
        heart.textContent = '❤️';
        gallery.style.position = 'relative'; // already is, but safety
        gallery.appendChild(heart);
        heart.addEventListener('animationend', () => heart.remove(), { once: true });
        setTimeout(() => { if (heart.parentNode) heart.remove(); }, 2200);
    }

    /* ── Aktif/Pasif Toggle ── */
    async function toggleActive() {
        const btn = document.getElementById('toggleBtn');
        if (!btn) return;
        btn.disabled = true;
        try {
            const res = await apiFetch(`/listings/${listingId}/toggle`, { method: 'PATCH' });
            _isActive = res.is_active;
            if (_isActive) {
                btn.className = 'btn-toggle';
                btn.textContent = '✓ Aktif — Pasife Al';
            } else {
                btn.className = 'btn-toggle passive';
                btn.textContent = '✕ Pasif — Aktif Yap';
            }
        } catch (_) { }
        btn.disabled = false;
    }

    async function submitReport() {
        const reason = document.getElementById('reportReason').value;
        const note = document.getElementById('reportNote').value.trim();
        const msg = document.getElementById('reportMsg');
        if (!reason) { msg.textContent = 'Lütfen bir neden seçin.'; msg.style.display = 'block'; return; }
        const btn = document.getElementById('reportSendBtn');
        btn.disabled = true; btn.textContent = 'Gönderiliyor...';
        try {
            await apiFetch('/reports', {
                method: 'POST',
                body: JSON.stringify({ listing_id: listingId, reason: reason + (note ? ': ' + note : '') }),
            });
            closeReportModal();
            alert('Şikayetiniz alındı. Teşekkür ederiz.');
        } catch (e) {
            msg.textContent = e.detail || 'Bir hata oluştu.';
            msg.style.display = 'block';
            btn.disabled = false; btn.textContent = 'Gönder';
        }
    }

    /* ── Silme ── */
    function openDeleteModal() {
        document.getElementById('deleteModal').classList.add('open');
    }
    function closeDeleteModal() {
        document.getElementById('deleteModal').classList.remove('open');
    }
    async function confirmDelete() {
        const btn = document.getElementById('deleteSendBtn');
        btn.disabled = true; btn.textContent = 'Siliniyor...';
        try {
            await apiFetch(`/listings/${listingId}`, { method: 'DELETE' });
            closeDeleteModal();
            window.location.href = '/';
        } catch (e) {
            btn.disabled = false; btn.textContent = 'Evet, Sil';
            alert(e.detail || 'Silme işlemi başarısız.');
        }
    }

    load();

// ── Inline handler'lardan taşınan event listener'lar ─────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    var backLinkEl = document.getElementById('backLink');
    if (backLinkEl) backLinkEl.addEventListener('click', function (e) {
        e.preventDefault();
        if (history.length > 1) history.back();
        else window.location.href = '/';
    });

    var btnCancelReport = document.getElementById('btnCancelReport');
    if (btnCancelReport) btnCancelReport.addEventListener('click', closeReportModal);
    var reportSendBtn = document.getElementById('reportSendBtn');
    if (reportSendBtn) reportSendBtn.addEventListener('click', submitReport);

    var btnCancelDelete = document.getElementById('btnCancelDelete');
    if (btnCancelDelete) btnCancelDelete.addEventListener('click', closeDeleteModal);
    var deleteSendBtn = document.getElementById('deleteSendBtn');
    if (deleteSendBtn) deleteSendBtn.addEventListener('click', confirmDelete);

    var lightbox = document.getElementById('lightbox');
    if (lightbox) lightbox.addEventListener('click', lbClickOutside);
    var btnLbClose = document.getElementById('btnLbClose');
    if (btnLbClose) btnLbClose.addEventListener('click', closeLb);
    var btnLbPrev = document.getElementById('btnLbPrev');
    if (btnLbPrev) btnLbPrev.addEventListener('click', function () { lbNav(-1); });
    var btnLbNext = document.getElementById('btnLbNext');
    if (btnLbNext) btnLbNext.addEventListener('click', function () { lbNav(1); });
});
