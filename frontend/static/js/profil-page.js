    // /profil/username path veya ?u=username query param
    const _pathMatch = window.location.pathname.match(/^\/profil\/(.+)$/);
    const params = new URLSearchParams(window.location.search);
    const username = _pathMatch ? decodeURIComponent(_pathMatch[1]) : params.get('u');
    if (!username) window.location.href = '/';

    let _profileUser = null;

    function escHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function formatDate(iso) {
        if (!iso) return '';
        try {
            const d = new Date(iso);
            return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', year: 'numeric' });
        } catch (_) {
            return '';
        }
    }

    async function loadProfile() {
        const inner = document.getElementById('profileInner');
        try {
            const user = await apiFetch(`/users/${encodeURIComponent(username)}`);
            _profileUser = user;

            // ── Dynamic SEO ──
            const _pName = user.full_name || user.username;
            const _pDesc = `${_pName} (@${user.username}) teqlif profilini görüntüle — ${user.listing_count ?? 0} ilan`;
            const _pUrl = `https://teqlif.com/profil/${encodeURIComponent(user.username)}`;
            document.title = `${_pName} (@${user.username}) — teqlif`;
            const _sm = (prop, val, attr = 'property') => {
                let el = document.querySelector(`meta[${attr}="${prop}"]`);
                if (!el) { el = document.createElement('meta'); el.setAttribute(attr, prop); document.head.appendChild(el); }
                el.setAttribute('content', val);
            };
            let _c = document.querySelector('link[rel="canonical"]');
            if (!_c) { _c = document.createElement('link'); _c.rel = 'canonical'; document.head.appendChild(_c); }
            _c.href = _pUrl;
            _sm('description', _pDesc, 'name');
            _sm('og:url', _pUrl);
            _sm('og:title', document.title);
            _sm('og:description', _pDesc);
            _sm('twitter:title', document.title, 'name');
            _sm('twitter:description', _pDesc, 'name');

            const myUser = Auth.getUser();
            const isOwn = myUser && myUser.username === user.username;
            const loggedIn = !!Auth.getToken();
            const isFollowing = !isOwn && loggedIn && !!(user.is_following);
            const isBlocked = !isOwn && loggedIn && !!(user.is_blocked);

            renderProfile(user, isOwn, isFollowing, loggedIn, isBlocked);
            loadListings(user.id);
            loadRatingSummary(user.id);
        } catch (e) {
            inner.innerHTML = `<div class="profile-not-found"><p>Kullanıcı bulunamadı.</p></div>`;
        }
    }

    // ── Follow list modal ──────────────────────────────────────────────

    let _modalFollowStates = {}; // userId → isFollowing
    let _modalLoggedIn = false;

    async function openFollowModal(userId, type, title) {
        const backdrop = document.getElementById('followModalBackdrop');
        const body = document.getElementById('followModalBody');
        document.getElementById('followModalTitle').textContent = title;
        body.innerHTML = '<div class="follow-modal-loading">Yükleniyor...</div>';
        backdrop.classList.add('open');
        document.body.style.overflow = 'hidden';

        _modalLoggedIn = !!Auth.getToken();
        _modalFollowStates = {};

        try {
            const list = await apiFetch(`/follows/${userId}/${type}`);
            renderFollowList(list, body);
        } catch (_) {
            body.innerHTML = '<div class="follow-empty">Liste yüklenemedi.</div>';
        }
    }

    function renderFollowList(list, body) {
        if (!list || list.length === 0) {
            body.innerHTML = '<div class="follow-empty">Henüz kimse yok.</div>';
            return;
        }
        list.forEach(u => { _modalFollowStates[u.id] = u.is_following; });

        body.innerHTML = list.map(u => {
            const initial = ((u.full_name || u.username || '?')[0]).toUpperCase();
            const btnHtml = (!u.is_me && _modalLoggedIn)
                ? `<button
                        id="fmbtn_${u.id}"
                        class="btn-follow-sm ${u.is_following ? 'following' : 'not-following'}"
                        onclick="toggleModalFollow(${u.id})"
                    >${u.is_following ? 'Takiptesin' : 'Takip Et'}</button>`
                : '';
            return `
                <div class="follow-user-row">
                    <a class="follow-user-avatar" href="/profil.html?u=${encodeURIComponent(u.username)}">${escHtml(initial)}</a>
                    <div class="follow-user-info">
                        <a class="follow-user-name" href="/profil.html?u=${encodeURIComponent(u.username)}">${escHtml(u.full_name || u.username)}</a>
                        <div class="follow-user-handle">@${escHtml(u.username)}</div>
                    </div>
                    ${btnHtml}
                </div>`;
        }).join('');
    }

    async function toggleModalFollow(userId) {
        const btn = document.getElementById(`fmbtn_${userId}`);
        if (!btn) return;
        const isFollowing = _modalFollowStates[userId];
        btn.disabled = true;
        try {
            if (isFollowing) {
                await apiFetch(`/follows/${userId}`, { method: 'DELETE' });
                _modalFollowStates[userId] = false;
                btn.className = 'btn-follow-sm not-following';
                btn.textContent = 'Takip Et';
            } else {
                await apiFetch(`/follows/${userId}`, { method: 'POST' });
                _modalFollowStates[userId] = true;
                btn.className = 'btn-follow-sm following';
                btn.textContent = 'Takiptesin';
            }
        } catch (_) { }
        finally { btn.disabled = false; }
    }

    function closeFollowModal(event) {
        if (event && event.target !== document.getElementById('followModalBackdrop')) return;
        document.getElementById('followModalBackdrop').classList.remove('open');
        document.body.style.overflow = '';
    }

    // ──────────────────────────────────────────────────────────────────

    const _blockSvg = `<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>`;

    function renderProfile(user, isOwn, isFollowing, loggedIn, isBlocked = false) {
        const inner = document.getElementById('profileInner');
        const initial = ((user.full_name || user.username || '?')[0]).toUpperCase();
        const listingCount = user.listing_count ?? 0;
        const followerCount = user.follower_count ?? 0;
        const followingCount = user.following_count ?? 0;

        let actionsHtml = '';

        const _shareSvg = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;margin-right:4px;"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>`;
        const _shareBtn = `<button class="btn-profile secondary" id="shareProfileBtn">${_shareSvg}Paylaş</button>`;

        if (isOwn) {
            actionsHtml = `
                <div class="profile-actions">
                    <button class="btn-profile secondary" onclick="openEditProfileModal()">
                        <svg viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                        Profili Düzenle
                    </button>
                    ${_shareBtn}
                </div>`;
        } else if (loggedIn) {
            const toName = encodeURIComponent(user.full_name || user.username);
            const toHandle = encodeURIComponent(user.username);
            const followBtnClass = isFollowing ? 'primary' : 'secondary';
            const followIcon = isFollowing
                ? `<svg viewBox="0 0 24 24"><path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="18" y1="8" x2="23" y2="13"/><line x1="23" y1="8" x2="18" y2="13"/></svg>`
                : `<svg viewBox="0 0 24 24"><path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/></svg>`;
            const followLabel = isFollowing ? 'Takip Ediliyor' : 'Takip Et';
            const rateBtn = isFollowing
                ? `<button class="btn-profile secondary" id="rateBtn" onclick="openRatingFormModal(${user.id})">
                        <svg viewBox="0 0 24 24"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.27 5.82 21 7 14.14l-5-4.87 6.91-1.01L12 2z" fill="currentColor" stroke="none"/></svg>
                        <span id="rateBtnLabel">Puan Ver</span>
                    </button>`
                : '';
            const blockLabel = isBlocked ? 'Engeli Kaldır' : 'Engelle';
            const blockBtn = `<button class="btn-block ${isBlocked ? 'blocked' : ''}" id="blockBtn" onclick="toggleBlock(${user.id}, ${isBlocked})">${_blockSvg} ${escHtml(blockLabel)}</button>`;
            actionsHtml = `
                <div class="profile-actions">
                    <button class="btn-profile ${followBtnClass}" id="followBtn" onclick="toggleFollow(${user.id}, ${isFollowing})">
                        ${followIcon}
                        <span id="followLabel">${escHtml(followLabel)}</span>
                    </button>
                    <a class="btn-profile primary" href="/mesajlar.html?to_id=${user.id}&to_name=${toName}&to_handle=${toHandle}">
                        <svg viewBox="0 0 24 24"><path d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/></svg>
                        Mesaj Gönder
                    </a>
                    ${rateBtn}
                    ${blockBtn}
                    ${_shareBtn}
                </div>`;
        } else {
            actionsHtml = `
                <div class="profile-actions">
                    <a class="btn-profile primary" href="/giris.html">Mesaj göndermek için giriş yap</a>
                    ${_shareBtn}
                </div>`;
        }

        const _innerAvatar = user.profile_image_url
            ? `<div class="profile-avatar" style="overflow:hidden;"><img src="${escHtml(user.profile_image_url)}" alt="${escHtml(user.full_name || user.username)}" style="width:100%;height:100%;object-fit:cover;border-radius:50%;"></div>`
            : `<div class="profile-avatar">${escHtml(initial)}</div>`;

        const avatarHtml = user.is_live
            ? `<div class="avatar-live-ring" onclick="goToLiveStream(${user.active_stream_id})" title="Canlı yayını izle">
                   ${_innerAvatar}
                   <span class="live-badge">● CANLI</span>
               </div>`
            : _innerAvatar;

        inner.innerHTML = `
            ${isOwn ? `
            <div class="profile-settings-row">
                <a href="/hesabim.html" class="btn-settings" title="Ayarlar">
                    <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></svg>
                </a>
            </div>` : ''}
            ${avatarHtml}
            <div class="profile-name">${escHtml(user.full_name || user.username)}</div>
            <div class="profile-handle">@${escHtml(user.username)}</div>
            <div id="ratingBadgeWrap"></div>
            <div class="stats-bar">
                <div class="stat-item">
                    <span class="stat-count">${listingCount}</span>
                    <span class="stat-label">İlanlar</span>
                </div>
                <div class="stat-divider"></div>
                <div class="stat-item clickable" onclick="openFollowModal(${user.id}, 'followers', 'Takipçiler')">
                    <span class="stat-count" id="followerCount">${followerCount}</span>
                    <span class="stat-label">Takipçi</span>
                </div>
                <div class="stat-divider"></div>
                <div class="stat-item clickable" onclick="openFollowModal(${user.id}, 'following', 'Takip Edilenler')">
                    <span class="stat-count">${followingCount}</span>
                    <span class="stat-label">Takip</span>
                </div>
            </div>
            ${actionsHtml}
            <div class="listings-section" id="listingsSection">
                <div class="listings-title">İlanları (–)</div>
                <div class="profile-loading" style="padding-top:1rem;">Yükleniyor...</div>
            </div>`;

        const shareProfileBtnEl = document.getElementById('shareProfileBtn');
        if (shareProfileBtnEl) shareProfileBtnEl.addEventListener('click', function () {
            const shareUrl = 'https://www.teqlif.com/profil/' + encodeURIComponent(user.username);
            const shareText = '@' + user.username + ' — teqlif\'te incele: ' + shareUrl;
            if (navigator.share) {
                navigator.share({ title: user.full_name || user.username, text: shareText, url: shareUrl }).catch(function(){});
            } else {
                navigator.clipboard.writeText(shareUrl).then(function () {
                    shareProfileBtnEl.textContent = '✓ Link kopyalandı';
                    setTimeout(function () { shareProfileBtnEl.innerHTML = _shareSvg + 'Paylaş'; }, 2000);
                }).catch(function () { window.prompt('Linki kopyala:', shareUrl); });
            }
        });
    }

    async function loadListings(userId) {
        const section = document.getElementById('listingsSection');
        if (!section) return;
        try {
            const listings = await apiFetch(`/listings?user_id=${userId}`);
            renderListings(listings, section);
        } catch (_) {
            if (section) {
                section.innerHTML = `<div class="listings-title">İlanları (0)</div><div class="empty-listings">İlanlar yüklenemedi.</div>`;
            }
        }
    }

    function renderListings(listings, section) {
        if (!section) return;
        const count = Array.isArray(listings) ? listings.length : 0;
        let html = `<div class="listings-title">İlanları (${count})</div>`;

        if (count === 0) {
            html += `
                <div class="empty-listings">
                    <div>
                        <svg viewBox="0 0 24 24"><rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 00-4 0v2"/></svg>
                    </div>
                    Henüz ilan yok
                </div>`;
        } else {
            html += `<div class="listings-grid">`;
            for (const l of listings) {
                const price = l.price != null ? `${Number(l.price).toLocaleString('tr-TR')} ₺` : '';
                const imgs = Array.isArray(l.image_urls) ? l.image_urls : [];
                const imgSrc = imgs.length > 0 ? imgs[0] : (l.image_url || null);
                const imgHtml = imgSrc
                    ? `<img src="${escHtml(imgSrc)}" alt="${escHtml(l.title)}" loading="lazy" onerror="this.parentElement.innerHTML='<div class=\\'listing-square-placeholder\\'><svg viewBox=\\'0 0 24 24\\'><rect x=\\'2\\' y=\\'7\\' width=\\'20\\' height=\\'14\\' rx=\\'2\\'/></svg></div>'">`
                    : `<div class="listing-square-placeholder"><svg viewBox="0 0 24 24" fill="none" stroke-width="1.5"><rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 00-4 0v2"/></svg></div>`;
                html += `
                    <div class="listing-square" onclick="location.href='/ilan/${l.id}'">
                        ${imgHtml}
                        <div class="listing-square-overlay">
                            ${price ? `<div class="listing-square-price">${escHtml(price)}</div>` : ''}
                            <div class="listing-square-title">${escHtml(l.title)}</div>
                        </div>
                    </div>`;
            }
            html += `</div>`;
        }

        section.innerHTML = html;
    }

    async function toggleFollow(userId, currentlyFollowing) {
        const btn = document.getElementById('followBtn');
        const label = document.getElementById('followLabel');
        if (!btn) return;

        btn.disabled = true;
        btn.style.opacity = '0.7';

        try {
            if (currentlyFollowing) {
                await apiFetch(`/follows/${userId}`, { method: 'DELETE' });
                // Update button to "Takip Et"
                btn.className = 'btn-profile secondary';
                btn.innerHTML = `
                    <svg viewBox="0 0 24 24" style="width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex-shrink:0"><path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/></svg>
                    <span id="followLabel">Takip Et</span>`;
                btn.setAttribute('onclick', `toggleFollow(${userId}, false)`);
                // Update follower count
                const fc = document.getElementById('followerCount');
                if (fc) fc.textContent = Math.max(0, parseInt(fc.textContent || '0') - 1);
            } else {
                await apiFetch(`/follows/${userId}`, { method: 'POST' });
                // Update button to "Takip Ediliyor"
                btn.className = 'btn-profile primary';
                btn.innerHTML = `
                    <svg viewBox="0 0 24 24" style="width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex-shrink:0"><path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="18" y1="8" x2="23" y2="13"/><line x1="23" y1="8" x2="18" y2="13"/></svg>
                    <span id="followLabel">Takip Ediliyor</span>`;
                btn.setAttribute('onclick', `toggleFollow(${userId}, true)`);
                // Update follower count
                const fc = document.getElementById('followerCount');
                if (fc) fc.textContent = parseInt(fc.textContent || '0') + 1;
            }
        } catch (e) {
            // On error, just re-enable
        } finally {
            btn.disabled = false;
            btn.style.opacity = '';
        }
    }

    // ── Canlı yayın navigasyonu ────────────────────────────────────
    function goToLiveStream(streamId) {
        if (!streamId) return;
        window.location.href = `/yayin.html?id=${streamId}`;
    }

    // ── Rating state ───────────────────────────────────────────────
    let _ratingUserId = null;
    let _ratingSelected = 0;
    const _starLabels = ['', 'Çok kötü', 'Kötü', 'Orta', 'İyi', 'Mükemmel'];

    // ── Load & render rating summary badge ─────────────────────────
    async function loadRatingSummary(userId) {
        const wrap = document.getElementById('ratingBadgeWrap');
        if (!wrap) return;
        try {
            const data = await apiFetch(`/ratings/${userId}/summary`);
            // Update "Puan Ver" button label if user already rated
            const rateLabel = document.getElementById('rateBtnLabel');
            if (rateLabel && data.my_rating) rateLabel.textContent = 'Puanı Güncelle';

            if (!data.average) {
                wrap.innerHTML = `<span class="rating-badge-empty">Henüz değerlendirme yok</span>`;
                return;
            }
            const filled = Math.round(data.average);
            const stars = '★'.repeat(filled) + '☆'.repeat(5 - filled);
            wrap.innerHTML = `
                <button class="rating-badge" onclick="openRatingsListModal(${userId})" title="Değerlendirmeleri gör">
                    <span class="rb-stars">${stars}</span>
                    <span class="rb-avg">${data.average.toFixed(1)}</span>
                    <span class="rb-count">${data.count} puan</span>
                </button>`;
        } catch (_) {
            wrap.innerHTML = '';
        }
    }

    // ── Rating form modal ──────────────────────────────────────────
    function openRatingFormModal(userId) {
        _ratingUserId = userId;
        _ratingSelected = 0;
        document.getElementById('ratingFormBackdrop').classList.add('open');
        document.body.style.overflow = 'hidden';

        // Reset state
        updateStarDisplay();
        document.getElementById('ratingStarLabel').textContent = 'Bir yıldız seçin';
        const commentEl = document.getElementById('ratingComment');
        commentEl.value = '';
        document.getElementById('ratingCharCount').textContent = '0';
        document.getElementById('ratingSubmitBtn').disabled = true;

        // Pre-fill if user already has a rating
        const rateLabel = document.getElementById('rateBtnLabel');
        const isUpdate = rateLabel && rateLabel.textContent === 'Puanı Güncelle';
        document.getElementById('ratingFormTitle').textContent = isUpdate ? 'Puanı Güncelle' : 'Puan Ver';

        // Try to prefill from summary cache (my_rating)
        apiFetch(`/ratings/${userId}/summary`).then(data => {
            if (data.my_rating) {
                _ratingSelected = data.my_rating.score;
                updateStarDisplay();
                if (data.my_rating.comment) commentEl.value = data.my_rating.comment;
                document.getElementById('ratingCharCount').textContent = commentEl.value.length;
                document.getElementById('ratingSubmitBtn').disabled = false;
            }
        }).catch(() => {});

        initStarPicker();
    }

    function closeRatingForm(event) {
        if (event && event.target !== document.getElementById('ratingFormBackdrop')) return;
        document.getElementById('ratingFormBackdrop').classList.remove('open');
        document.body.style.overflow = '';
    }

    function initStarPicker() {
        const stars = document.querySelectorAll('#ratingStarPicker span');
        stars.forEach(star => {
            star.onmouseenter = () => {
                const v = parseInt(star.dataset.v);
                stars.forEach(s => s.classList.toggle('lit', parseInt(s.dataset.v) <= v));
            };
            star.onmouseleave = () => {
                stars.forEach(s => s.classList.toggle('lit', parseInt(s.dataset.v) <= _ratingSelected));
            };
            star.onclick = () => {
                _ratingSelected = parseInt(star.dataset.v);
                updateStarDisplay();
                document.getElementById('ratingStarLabel').textContent = _starLabels[_ratingSelected] || '';
                document.getElementById('ratingSubmitBtn').disabled = false;
            };
        });

        // Comment char counter
        const commentEl = document.getElementById('ratingComment');
        commentEl.oninput = () => {
            document.getElementById('ratingCharCount').textContent = commentEl.value.length;
        };
    }

    function updateStarDisplay() {
        document.querySelectorAll('#ratingStarPicker span').forEach(s => {
            s.classList.toggle('lit', parseInt(s.dataset.v) <= _ratingSelected);
        });
    }

    async function submitRating() {
        if (!_ratingUserId || !_ratingSelected) return;
        const btn = document.getElementById('ratingSubmitBtn');
        btn.disabled = true;
        btn.textContent = 'Kaydediliyor...';
        const comment = document.getElementById('ratingComment').value.trim();
        try {
            await apiFetch(`/ratings/${_ratingUserId}`, {
                method: 'POST',
                body: JSON.stringify({ score: _ratingSelected, comment: comment || null }),
            });
            closeRatingForm(null);
            // Refresh badge and update button label
            const rateLabel = document.getElementById('rateBtnLabel');
            if (rateLabel) rateLabel.textContent = 'Puanı Güncelle';
            loadRatingSummary(_ratingUserId);
        } catch (e) {
            btn.disabled = false;
            btn.textContent = 'Kaydet';
            alert((e && e.detail) || 'Bir hata oluştu.');
        }
    }

    // ── Ratings list modal ─────────────────────────────────────────
    async function openRatingsListModal(userId) {
        document.getElementById('ratingsListBackdrop').classList.add('open');
        document.body.style.overflow = 'hidden';
        const body = document.getElementById('ratingsListBody');
        const summaryBar = document.getElementById('ratingsListSummaryBar');
        body.innerHTML = '<div class="follow-modal-loading">Yükleniyor...</div>';
        summaryBar.innerHTML = '';
        try {
            const [listResult, summaryResult] = await Promise.allSettled([
                apiFetch(`/ratings/${userId}`),
                apiFetch(`/ratings/${userId}/summary`),
            ]);
            const list = listResult.status === 'fulfilled' ? listResult.value : [];
            const summary = summaryResult.status === 'fulfilled' ? summaryResult.value : {};
            // Summary bar
            if (summary?.average) {
                const filled = Math.round(summary.average);
                summaryBar.innerHTML = `
                    <div class="ratings-summary-bar">
                        <div class="rsb-avg">${summary.average.toFixed(1)}</div>
                        <div>
                            <span class="rsb-stars">${'★'.repeat(filled)}${'☆'.repeat(5 - filled)}</span>
                            <span class="rsb-count">${summary.count} değerlendirme</span>
                        </div>
                    </div>`;
            }
            renderRatingsList(list, body);
        } catch (_) {
            body.innerHTML = '<div class="follow-empty">Değerlendirmeler yüklenemedi.</div>';
        }
    }

    function closeRatingsList(event) {
        if (event && event.target !== document.getElementById('ratingsListBackdrop')) return;
        document.getElementById('ratingsListBackdrop').classList.remove('open');
        document.body.style.overflow = '';
    }

    function renderRatingsList(list, body) {
        if (!list || list.length === 0) {
            body.innerHTML = '<div class="follow-empty">Henüz değerlendirme yok.</div>';
            return;
        }
        body.innerHTML = list.map(r => {
            const u = r.rater;
            const initial = ((u.full_name || u.username || '?')[0]).toUpperCase();
            const stars = '★'.repeat(r.score) + '☆'.repeat(5 - r.score);
            const avatarHtml = u.profile_image_url
                ? `<img src="${escHtml(u.profile_image_url)}" style="width:100%;height:100%;object-fit:cover;" alt="">`
                : escHtml(initial);
            return `
                <div class="rating-row">
                    <a class="rating-row-avatar" href="/profil/${encodeURIComponent(u.username)}">${avatarHtml}</a>
                    <div class="rating-row-info">
                        <div class="rating-row-top">
                            <a class="rating-row-name" href="/profil/${encodeURIComponent(u.username)}">${escHtml(u.full_name || u.username)}</a>
                            <span class="rating-row-stars">${stars}</span>
                        </div>
                        ${r.comment ? `<div class="rating-row-comment">${escHtml(r.comment)}</div>` : ''}
                        <div class="rating-row-date">${formatDate(r.updated_at || r.created_at)}</div>
                    </div>
                </div>`;
        }).join('');
    }

    // ── Kullanıcı engelleme ────────────────────────────────────────
    async function toggleBlock(userId, currentlyBlocked) {
        const btn = document.getElementById('blockBtn');
        if (!btn) return;
        btn.disabled = true;
        try {
            if (currentlyBlocked) {
                await apiFetch(`/users/${encodeURIComponent(username)}/block`, { method: 'DELETE' });
                btn.className = 'btn-block';
                btn.innerHTML = `${_blockSvg} Engelle`;
                btn.setAttribute('onclick', `toggleBlock(${userId}, false)`);
            } else {
                await apiFetch(`/users/${encodeURIComponent(username)}/block`, { method: 'POST' });
                btn.className = 'btn-block blocked';
                btn.innerHTML = `${_blockSvg} Engeli Kaldır`;
                btn.setAttribute('onclick', `toggleBlock(${userId}, true)`);
            }
        } catch (e) {
            alert((e && e.detail) || 'İşlem gerçekleştirilemedi.');
        } finally {
            btn.disabled = false;
        }
    }

    // ── Profil düzenleme modal ─────────────────────────────────────
    function openEditProfileModal() {
        const user = _profileUser;
        if (!user) return;
        document.getElementById('epFullName').value = user.full_name || '';
        document.getElementById('epUsername').value = user.username || '';
        document.getElementById('epUsernameHint').textContent = 'Yalnızca küçük harf, rakam ve alt çizgi (_) kullanılabilir.';
        document.getElementById('epUsernameHint').style.color = '#9ca3af';
        document.getElementById('epSaveBtn').disabled = false;
        document.getElementById('epBackdrop').classList.add('open');
        document.body.style.overflow = 'hidden';
        document.getElementById('epFullName').focus();
    }

    function closeEditProfileModal(event) {
        if (event && event.target !== document.getElementById('epBackdrop')) return;
        document.getElementById('epBackdrop').classList.remove('open');
        document.body.style.overflow = '';
    }

    function epUsernameInput(input) {
        const hint = document.getElementById('epUsernameHint');
        const val = input.value;
        if (val && !/^[a-z0-9_]{3,50}$/.test(val)) {
            hint.textContent = 'Geçersiz format — küçük harf, rakam ve _ kullanılabilir (3-50 karakter).';
            hint.style.color = '#ef4444';
        } else {
            hint.textContent = 'Yalnızca küçük harf, rakam ve alt çizgi (_) kullanılabilir.';
            hint.style.color = '#9ca3af';
        }
    }

    async function submitEditProfile() {
        const fullName = document.getElementById('epFullName').value.trim();
        const newUsername = document.getElementById('epUsername').value.trim();
        const btn = document.getElementById('epSaveBtn');

        if (!fullName || fullName.length < 2) {
            alert('Ad Soyad en az 2 karakter olmalıdır.');
            return;
        }
        if (!newUsername || !/^[a-z0-9_]{3,50}$/.test(newUsername)) {
            alert('Geçersiz kullanıcı adı formatı.');
            return;
        }

        btn.disabled = true;
        btn.textContent = 'Kaydediliyor...';
        try {
            const updated = await apiFetch('/auth/me', {
                method: 'PATCH',
                body: JSON.stringify({ full_name: fullName, username: newUsername }),
            });
            // Local state güncelle
            _profileUser.full_name = updated.full_name;
            _profileUser.username = updated.username;
            // Auth storage güncelle
            const storedUser = Auth.getUser();
            if (storedUser) {
                storedUser.full_name = updated.full_name;
                storedUser.username = updated.username;
                localStorage.setItem('teqlif_user', JSON.stringify(storedUser));
            }
            closeEditProfileModal(null);
            // UI güncelle
            document.querySelector('.profile-name').textContent = updated.full_name || updated.username;
            document.querySelector('.profile-handle').textContent = '@' + updated.username;
        } catch (e) {
            alert((e && e.message) || (e && e.detail) || 'Profil güncellenemedi.');
        } finally {
            btn.disabled = false;
            btn.textContent = 'Kaydet';
        }
    }

    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') {
            closeRatingForm(null);
            closeRatingsList(null);
            closeEditProfileModal(null);
        }
    });

    loadProfile();

// ── Inline handler'lardan taşınan event listener'lar ─────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    var followModalBackdrop = document.getElementById('followModalBackdrop');
    if (followModalBackdrop) followModalBackdrop.addEventListener('click', closeFollowModal);
    var btnCloseFollowModal = document.getElementById('btnCloseFollowModal');
    if (btnCloseFollowModal) btnCloseFollowModal.addEventListener('click', function () { closeFollowModal(null); });

    var ratingFormBackdrop = document.getElementById('ratingFormBackdrop');
    if (ratingFormBackdrop) ratingFormBackdrop.addEventListener('click', closeRatingForm);
    var btnCloseRatingForm = document.getElementById('btnCloseRatingForm');
    if (btnCloseRatingForm) btnCloseRatingForm.addEventListener('click', function () { closeRatingForm(null); });
    var btnCancelRating = document.getElementById('btnCancelRating');
    if (btnCancelRating) btnCancelRating.addEventListener('click', function () { closeRatingForm(null); });
    var ratingSubmitBtn = document.getElementById('ratingSubmitBtn');
    if (ratingSubmitBtn) ratingSubmitBtn.addEventListener('click', submitRating);

    var ratingsListBackdrop = document.getElementById('ratingsListBackdrop');
    if (ratingsListBackdrop) ratingsListBackdrop.addEventListener('click', closeRatingsList);
    var btnCloseRatingsList = document.getElementById('btnCloseRatingsList');
    if (btnCloseRatingsList) btnCloseRatingsList.addEventListener('click', function () { closeRatingsList(null); });

    var epBackdrop = document.getElementById('epBackdrop');
    if (epBackdrop) epBackdrop.addEventListener('click', closeEditProfileModal);
    var btnCloseEpModal = document.getElementById('btnCloseEpModal');
    if (btnCloseEpModal) btnCloseEpModal.addEventListener('click', function () { closeEditProfileModal(null); });
    var epUsernameInputEl = document.getElementById('epUsernameInputEl') || document.getElementById('epUsername');
    if (epUsernameInputEl) epUsernameInputEl.addEventListener('input', function () { epUsernameInput(this); });
    var btnEpCancel = document.getElementById('btnEpCancel');
    if (btnEpCancel) btnEpCancel.addEventListener('click', function () { closeEditProfileModal(null); });
    var epSaveBtn = document.getElementById('epSaveBtn');
    if (epSaveBtn) epSaveBtn.addEventListener('click', submitEditProfile);
});
