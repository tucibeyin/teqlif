    const alertEl = document.getElementById('alert');
    const btnYayınAc = document.getElementById('btnYayınAc');
    const btnIlanVer = document.getElementById('btnIlanVer');
    const startModal = document.getElementById('startModal');
    const modalAlert = document.getElementById('modalAlert');

    btnYayınAc.style.display = ''; // Initially show as 'Canlı Yayınlar' is active by default

    /* ── Tab geçişi ─────────────────────────────────────────────── */
    function switchTab(tab) {
        const isCanli = tab === 'canli';
        document.getElementById('section-canli').style.display = isCanli ? '' : 'none';
        document.getElementById('section-ilanlar').style.display = isCanli ? 'none' : '';
        document.getElementById('tab-canli').classList.toggle('active', isCanli);
        document.getElementById('tab-ilanlar').classList.toggle('active', !isCanli);
        btnYayınAc.style.display = isCanli ? '' : 'none';
        btnIlanVer.style.display = !isCanli ? '' : 'none';
        if (!isCanli && !_listingsLoaded) { loadListings(); loadCityOptions(); }
        
        // URL Hash senkronizasyonu
        if (!isCanli && window.location.hash !== '#ilanlar') {
            history.replaceState(null, null, '#ilanlar');
        } else if (isCanli && window.location.hash === '#ilanlar') {
            history.replaceState(null, null, window.location.pathname + window.location.search);
        }
    }

    /* ── Canlı yayınlar ─────────────────────────────────────────── */
    const grid = document.getElementById('streamsGrid');
    const loadingState = document.getElementById('loadingState');
    const streamCatBar = document.getElementById('streamCatBar');

    const STREAM_CAT_LABELS = {
        elektronik: '📱 Elektronik',
        giyim: '👗 Giyim',
        ev: '🏠 Ev & Yaşam',
        vasita: '🚗 Vasıta',
        spor: '⚽ Spor',
        kitap: '📚 Kitap',
        emlak: '🏘️ Emlak',
        diger: '📦 Diğer',
    };

    let _allStreams = [];
    let _activeCatStream = '';

    function _streamCardHtml(s) {
        return `<div class="stream-card" data-stream-id="${s.id}" style="cursor:pointer">
            <div class="stream-thumb">
                <span class="live-badge">CANLI</span>
                <span class="viewer-badge">👁 ${s.viewer_count}</span>
                ${s.thumbnail_url
                ? `<img class="stream-thumb-img" src="${escHtml(s.thumbnail_url)}" alt="${escHtml(s.title)}" loading="lazy" onerror="this.remove()">`
                : ''
            }
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.5">
                    <path d="M15 10l4.553-2.07A1 1 0 0121 8.845v6.31a1 1 0 01-1.447.894L15 14M3 8a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z"/>
                </svg>
            </div>
            <div class="stream-info">
                <div class="stream-title">${escHtml(s.title)}</div>
                <div class="stream-host"><a href="/profil.html?u=${encodeURIComponent(s.host.username)}" data-stop-propagation="1" style="color:var(--primary);text-decoration:none;">@${escHtml(s.host.username)}</a></div>
                <button class="btn btn-primary btn-full" data-join-stream="${s.id}">Katıl</button>
            </div>
        </div>`;
    }

    function _renderStreams() {
        const filtered = _activeCatStream
            ? _allStreams.filter(s => s.category === _activeCatStream)
            : _allStreams;

        if (!filtered.length) {
            grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M15 10l4.553-2.07A1 1 0 0121 8.845v6.31a1 1 0 01-1.447.894L15 14M3 8a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z"/></svg>
                <p>${_activeCatStream ? 'Bu kategoride aktif yayın yok.' : 'Şu an aktif yayın yok.'}</p>
                ${!_activeCatStream ? '<p style="font-size:0.85rem;margin-top:0.5rem;">İlk yayını sen başlat!</p>' : ''}
            </div>`;
            return;
        }

        if (_activeCatStream) {
            grid.innerHTML = filtered.map(_streamCardHtml).join('');
        } else {
            const cats = [...new Set(filtered.map(s => s.category))];
            if (cats.length < 2) {
                grid.innerHTML = filtered.map(_streamCardHtml).join('');
            } else {
                grid.innerHTML = cats.map(cat => {
                    const label = STREAM_CAT_LABELS[cat] || cat;
                    const items = filtered.filter(s => s.category === cat);
                    return `<div class="stream-section-title">${label}</div>` + items.map(_streamCardHtml).join('');
                }).join('');
            }
        }
    }

    function filterStreamCat(el, cat) {
        document.querySelectorAll('#streamCatBar .cat-pill').forEach(p => p.classList.remove('active'));
        el.classList.add('active');
        _activeCatStream = cat;
        _renderStreams();
    }

    async function loadStreams() {
        try {
            const streams = await apiFetch('/streams/active');
            loadingState.remove();
            _allStreams = streams;
            _renderStreams();
        } catch (err) {
            loadingState.innerHTML = '<p>Yayınlar yüklenemedi.</p>';
        }
    }

    /* ── Story Tray: Hybrid hikayeler + "Hikayen" butonu ───────── */

    /**
     * Karma (video + canlı yayın) story tepsisini render eder.
     *
     * Index 0 → "Hikayen" (+) butonu — her zaman gösterilir (login varsa).
     * Index 1+ → /api/stories/following'den gelen kullanıcı grupları.
     *
     * Canlı yayın içeren grup → kırmızı halka + CANLI badge.
     * Tıklama → canlı varsa joinStream(), yoksa web izleyici henüz yok.
     */
    // ── Story Viewer state ────────────────────────────────────────
    let _svGroups       = [];  // List<{user, items[], isMine}>
    let _svGroupIdx     = 0;
    let _svItemIdx      = 0;
    let _svTimer        = null;
    let _svProgressAnim = null;
    let _svCurrentUserId  = null;
    let _svCurrentLiked   = false;
    let _svCurrentLikesCount = 0;

    async function loadFollowedStories() {
        if (!Auth.getToken()) return;

        const wrapper = document.getElementById('storyTrayWrapper');
        const tray    = document.getElementById('storyTray');

        const me      = Auth.getUser();
        const myName  = me?.username ?? '';
        const myInitial = myName.charAt(0).toUpperCase() || '?';

        // ── Kendi hikayeleri + takip edilen gruplar (paralel) ─────
        let myItems = [], groups = [];
        try {
            [myItems, groups] = await Promise.all([
                apiFetch('/stories/mine').then(r => r?.items ?? []).catch(() => []),
                apiFetch('/stories/following').then(r => Array.isArray(r) ? r : []).catch(() => []),
            ]);
        } catch (err) {
            console.error('[StoryTray] Yükleme hatası:', err);
            if (window.Sentry) Sentry.captureException(err);
        }

        const hasMyStories = myItems.length > 0;

        // ── "Hikayen" butonu ─────────────────────────────────────
        const myRingStyle = hasMyStories
            ? 'background:linear-gradient(135deg,var(--color-primary,#6366f1) 0%,#7c3aed 100%)'
            : '';
        const myStoryHtml = `
            <div class="story-item story-add-btn" id="myStoryBtn"
                 title="${hasMyStories ? 'Hikayeni gör' : 'Video hikayeni paylaş'}"
                 data-story-action="${hasMyStories ? 'open-mine' : 'upload'}"
                 style="cursor:pointer">
                <div class="story-ring-wrap">
                    <div class="story-ring" style="${myRingStyle}">
                        <div class="story-ring-inner" id="myStoryInner">
                            <div class="story-avatar-initials">${myInitial}</div>
                        </div>
                    </div>
                    <div class="story-add-badge" id="myStoryBadge"
                         data-story-action="upload" data-stop-propagation="1">+</div>
                </div>
                <span class="story-username">Hikayen</span>
            </div>`;

        // ── Takip edilen gruplar ──────────────────────────────────
        const groupsHtml = groups.map((g, gi) => {
            const username = g.user?.username ?? '';
            const initial  = username.charAt(0).toUpperCase() || '?';
            const rawUrl   = g.user?.profile_image_thumb_url ?? g.user?.profile_image_url ?? null;
            const imgUrl   = rawUrl
                ? (rawUrl.startsWith('http') ? rawUrl : '/api' + rawUrl)
                : null;

            const liveItem = Array.isArray(g.items)
                ? g.items.find(i => i.story_type === 'live_redirect')
                : null;
            const hasLive  = !!liveItem;
            const hasVideo = Array.isArray(g.items) && g.items.some(i => i.story_type === 'video' || i.story_type === 'image');

            const ringStyle = hasLive
                ? 'background:linear-gradient(135deg,#ff4136 0%,#ff851b 100%)'
                : '';

            const avatarHtml = imgUrl
                ? `<img class="story-avatar" src="${imgUrl}" alt="${username}" loading="lazy"
                          onerror="this.style.display='none';this.nextElementSibling.style.display='flex';">
                   <div class="story-avatar-initials" style="display:none;">${initial}</div>`
                : `<div class="story-avatar-initials">${initial}</div>`;

            const liveBadge = hasLive
                ? `<span style="position:absolute;bottom:0;right:0;background:#ff4136;color:#fff;
                               font-size:6.5px;font-weight:800;padding:1.5px 3.5px;
                               border-radius:3px;letter-spacing:.3px;line-height:1.2;
                               border:1px solid #fff;">CANLI</span>`
                : '';

            let storyDataAttr;
            if (hasLive) {
                storyDataAttr = `data-story-stream="${liveItem.stream_id}" style="cursor:pointer"`;
            } else if (hasVideo) {
                storyDataAttr = `data-story-group="${gi}" style="cursor:pointer"`;
            } else {
                storyDataAttr = 'style="cursor:default"';
            }

            return `
                <div class="story-item" ${storyDataAttr}
                     title="${username}${hasLive ? ' — Canlı Yayında' : ''}"
                     data-track-id="story-tray-item-${g.user?.id ?? ''}">
                    <div style="position:relative;width:60px;height:60px;flex-shrink:0;">
                        <div class="story-ring" style="${ringStyle}">
                            <div class="story-ring-inner">${avatarHtml}</div>
                        </div>
                        ${liveBadge}
                    </div>
                    <span class="story-username">${username}</span>
                </div>`;
        }).join('');

        // Viewer için grupları kaydet
        _svGroups = groups.map(g => ({ ...g, isMine: false }));
        _svCurrentUserId = me?.id ?? null;

        tray.innerHTML = myStoryHtml + groupsHtml;
        wrapper.style.display = 'block';

        // Kendi hikayeleri ayrı grup olarak viewer state'e ekle
        if (hasMyStories) {
            _svGroups = [
                { user: { id: me?.id, username: myName, full_name: me?.full_name ?? '' }, items: myItems, isMine: true },
                ..._svGroups,
            ];
        }
    }

    // ── Story Viewer API ──────────────────────────────────────────

    function svOpenMine() {
        const mineIdx = _svGroups.findIndex(g => g.isMine);
        if (mineIdx >= 0) svOpen(mineIdx);
    }

    function svOpenGroup(followingIdx) {
        // following groups start at index 1 if mine exists, else 0
        const hasMine = _svGroups.length > 0 && _svGroups[0].isMine;
        svOpen(hasMine ? followingIdx + 1 : followingIdx);
    }

    let _svActive = false; // viewer açık mı?

    function svOpen(groupIdx) {
        if (!_svGroups.length) return;
        _svGroupIdx = groupIdx;
        _svItemIdx  = 0;
        _svActive   = true;
        document.getElementById('storyViewerOverlay').style.display = 'block';
        document.body.style.overflow = 'hidden';
        svLoadItem();
    }

    function svClose() {
        _svActive = false;
        const overlay = document.getElementById('storyViewerOverlay');
        overlay.style.display = 'none';
        document.body.style.overflow = '';
        const video = document.getElementById('svVideo');
        video.oncanplay = null;
        video.onended   = null;
        video.onerror   = null;
        video.onloadedmetadata = null;
        video.pause();
        video.src = '';
        video.load(); // tarayıcının buffer'ını temizle
        video.style.display = 'none';
        const imgEl = document.getElementById('svImage');
        imgEl.onload  = null;
        imgEl.onerror = null;
        imgEl.src = '';
        imgEl.style.display = 'none';
        clearTimeout(_svTimer);
        cancelAnimationFrame(_svProgressAnim);
        document.getElementById('svSpinner').style.display = 'flex';
    }

    function svNavigate(dir) {
        const group = _svGroups[_svGroupIdx];
        const mediaItems = (group?.items ?? []).filter(i => i.story_type !== 'live_redirect');
        const newItem = _svItemIdx + dir;
        if (newItem >= 0 && newItem < mediaItems.length) {
            _svItemIdx = newItem;
            svLoadItem();
        } else if (dir > 0) {
            // Sonraki grup
            if (_svGroupIdx + 1 < _svGroups.length) {
                _svGroupIdx++;
                _svItemIdx = 0;
                svLoadItem();
            } else {
                svClose();
            }
        } else {
            // Önceki grup
            if (_svGroupIdx > 0) {
                _svGroupIdx--;
                const prevGroup = _svGroups[_svGroupIdx];
                const prevItems = (prevGroup?.items ?? []).filter(i => i.story_type !== 'live_redirect');
                _svItemIdx = Math.max(0, prevItems.length - 1);
                svLoadItem();
            } else {
                svClose();
            }
        }
    }

    function svLoadItem() {
        clearTimeout(_svTimer);
        cancelAnimationFrame(_svProgressAnim);

        const group = _svGroups[_svGroupIdx];
        if (!group) { svClose(); return; }

        const mediaItems = (group.items ?? []).filter(i => i.story_type !== 'live_redirect');
        if (!mediaItems.length) { svNavigate(1); return; }

        const item = mediaItems[_svItemIdx];

        // Beğeni durumunu güncelle
        _svCurrentLiked      = item.is_liked      ?? false;
        _svCurrentLikesCount = item.likes_count    ?? 0;
        const likeBtn  = document.getElementById('svLikeBtn');
        const likeIcon = document.getElementById('svLikeIcon');
        const likeCnt  = document.getElementById('svLikeCount');
        if (likeBtn) {
            // Kendi hikayen değilse butonu göster
            likeBtn.style.display = group.isMine ? 'none' : 'flex';
            if (likeIcon) {
                likeIcon.setAttribute('fill',   _svCurrentLiked ? '#e53e3e' : 'none');
                likeIcon.setAttribute('stroke', _svCurrentLiked ? '#e53e3e' : '#fff');
            }
            if (likeCnt) {
                likeCnt.textContent = _svCurrentLikesCount > 0 ? _svCurrentLikesCount : '';
            }
        }

        // Progress barlar
        svUpdateProgressBars(mediaItems.length);

        // Kullanıcı bar
        svUpdateUserBar(group);

        // Kim Gördü? butonu
        document.getElementById('svViewersBtn').style.display =
            group.isMine ? 'block' : 'none';
        if (group.isMine) {
            document.getElementById('svViewersBtn').dataset.storyId = item.id;
        }

        const video = document.getElementById('svVideo');
        const imgEl = document.getElementById('svImage');
        const spinner = document.getElementById('svSpinner');

        // Görüntüleme kaydı yardımcısı
        function recordView() {
            const token = Auth.getToken();
            if (token) {
                fetch(`/api/stories/${item.id}/view`, {
                    method: 'POST',
                    headers: { 'Authorization': `Bearer ${token}` },
                }).catch(() => {});
            }
        }

        // Progress animasyonu yardımcısı (ms cinsinden süre)
        function startProgress(durationMs) {
            const barFill = document.getElementById(`sv-bar-fill-${_svItemIdx}`);
            const animStart = performance.now();
            function tick() {
                if (!_svActive || !barFill) return;
                const elapsed = performance.now() - animStart;
                barFill.style.width = Math.min(elapsed / durationMs * 100, 100) + '%';
                if (elapsed < durationMs) {
                    _svProgressAnim = requestAnimationFrame(tick);
                }
            }
            _svProgressAnim = requestAnimationFrame(tick);
        }

        if (item.story_type === 'image') {
            // ── Fotoğraf hikayesi ──────────────────────────────────────
            video.style.display = 'none';
            video.oncanplay = null;
            video.onended = null;
            video.onerror = null;
            video.src = '';

            imgEl.style.display = 'none';
            spinner.style.display = 'flex';

            const rawUrl = item.thumbnail_url || item.video_url || '';
            imgEl.src = rawUrl.startsWith('http') || rawUrl.startsWith('/uploads')
                ? rawUrl
                : '/api' + rawUrl;

            imgEl.onload = () => {
                if (!_svActive) return;
                spinner.style.display = 'none';
                imgEl.style.display = 'block';
                recordView();
                const IMAGE_DURATION = 5000;
                startProgress(IMAGE_DURATION);
                _svTimer = setTimeout(() => { if (_svActive) svNavigate(1); }, IMAGE_DURATION);
            };
            imgEl.onerror = () => { if (_svActive) svNavigate(1); };
        } else {
            // ── Video hikayesi ─────────────────────────────────────────
            imgEl.style.display = 'none';
            imgEl.onload = null;
            imgEl.onerror = null;
            imgEl.src = '';

            video.style.display = 'none';
            spinner.style.display = 'flex';
            video.src = item.video_url.startsWith('http') || item.video_url.startsWith('/uploads')
                ? item.video_url
                : '/api' + item.video_url;
            video.load();

            let duration = 0;
            video.onloadedmetadata = () => { duration = video.duration * 1000; };
            video.oncanplay = () => {
                if (!_svActive) return;
                spinner.style.display = 'none';
                video.style.display = 'block';
                video.play().catch(() => {});
                recordView();
                startProgress(duration || (video.duration * 1000) || 10000);
            };
            video.onended = () => { if (_svActive) svNavigate(1); };
            video.onerror = () => { if (_svActive) svNavigate(1); };
        }
    }

    async function svToggleLike() {
        const group = _svGroups[_svGroupIdx];
        if (!group || group.isMine) return;
        const mediaItems = (group.items ?? []).filter(i => i.story_type !== 'live_redirect');
        const item = mediaItems[_svItemIdx];
        if (!item) return;

        // Optimistic update
        const prevLiked = _svCurrentLiked;
        const prevCount = _svCurrentLikesCount;
        _svCurrentLiked = !_svCurrentLiked;
        _svCurrentLikesCount += _svCurrentLiked ? 1 : -1;
        item.is_liked    = _svCurrentLiked;
        item.likes_count = _svCurrentLikesCount;

        const likeIcon = document.getElementById('svLikeIcon');
        const likeCnt  = document.getElementById('svLikeCount');
        if (likeIcon) {
            likeIcon.setAttribute('fill',   _svCurrentLiked ? '#e53e3e' : 'none');
            likeIcon.setAttribute('stroke', _svCurrentLiked ? '#e53e3e' : '#fff');
        }
        if (likeCnt) likeCnt.textContent = _svCurrentLikesCount > 0 ? _svCurrentLikesCount : '';

        if (_svCurrentLiked) svTriggerHeart();

        try {
            const result = await apiFetch(`/stories/${item.id}/like`, { method: 'POST' });
            _svCurrentLiked      = result.is_liked      ?? _svCurrentLiked;
            _svCurrentLikesCount = result.likes_count   ?? _svCurrentLikesCount;
            item.is_liked    = _svCurrentLiked;
            item.likes_count = _svCurrentLikesCount;
            if (likeIcon) {
                likeIcon.setAttribute('fill',   _svCurrentLiked ? '#e53e3e' : 'none');
                likeIcon.setAttribute('stroke', _svCurrentLiked ? '#e53e3e' : '#fff');
            }
            if (likeCnt) likeCnt.textContent = _svCurrentLikesCount > 0 ? _svCurrentLikesCount : '';
        } catch (_) {
            // Sessiz rollback
            _svCurrentLiked      = prevLiked;
            _svCurrentLikesCount = prevCount;
            item.is_liked    = prevLiked;
            item.likes_count = prevCount;
            if (likeIcon) {
                likeIcon.setAttribute('fill',   prevLiked ? '#e53e3e' : 'none');
                likeIcon.setAttribute('stroke', prevLiked ? '#e53e3e' : '#fff');
            }
            if (likeCnt) likeCnt.textContent = prevCount > 0 ? prevCount : '';
        }
    }

    function svTriggerHeart() {
        const overlay = document.getElementById('storyViewerOverlay');
        if (!overlay) return;
        const heart = document.createElement('div');
        heart.className = 'floating-heart';
        const driftX = (Math.random() * 40 - 20) | 0;
        heart.style.setProperty('--hx', `${driftX}px`);
        heart.textContent = '❤️';
        overlay.appendChild(heart);
        heart.addEventListener('animationend', () => heart.remove(), { once: true });
        // Güvenlik yedek temizleme (animationend tetiklenmezse)
        setTimeout(() => { if (heart.parentNode) heart.remove(); }, 2200);
    }

    function svUpdateProgressBars(total) {
        const container = document.getElementById('svProgressBars');
        container.innerHTML = Array.from({ length: total }, (_, i) => `
            <div style="flex:1;height:2.5px;background:rgba(255,255,255,.35);border-radius:2px;overflow:hidden;">
                <div id="sv-bar-fill-${i}"
                     style="height:100%;background:#fff;width:${i < _svItemIdx ? '100%' : '0%'};transition:none;"></div>
            </div>`).join('');
    }

    function svUpdateUserBar(group) {
        const bar = document.getElementById('svUserBar');
        const initial = (group.user?.username ?? '?').charAt(0).toUpperCase();
        const menuBtn = group.isMine ? `
            <div style="position:relative;margin-left:8px;">
                <button id="svMenuBtn" style="background:none;border:none;color:#fff;font-size:22px;cursor:pointer;line-height:1;padding:4px 6px;text-shadow:0 1px 4px rgba(0,0,0,.5);">⋯</button>
                <div id="svMenuDropdown" style="display:none;position:absolute;top:32px;right:0;background:#fff;border-radius:10px;box-shadow:0 4px 16px rgba(0,0,0,.18);min-width:150px;z-index:10;overflow:hidden;">
                    <button id="svDeleteBtn" style="display:flex;align-items:center;gap:8px;width:100%;padding:12px 16px;border:none;background:none;color:#e53e3e;font-size:14px;cursor:pointer;font-weight:500;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 011-1h4a1 1 0 011 1v2"/></svg>
                        Hikayeyi Sil
                    </button>
                </div>
            </div>` : '';
        bar.innerHTML = `
            <div style="width:34px;height:34px;border-radius:50%;border:1.5px solid #fff;overflow:hidden;background:rgba(255,255,255,.15);display:flex;align-items:center;justify-content:center;font-weight:700;color:#fff;font-size:14px;">${initial}</div>
            <span style="margin-left:9px;color:#fff;font-size:13.5px;font-weight:600;text-shadow:0 1px 4px rgba(0,0,0,.5);">${group.user?.username ?? ''}</span>
            <div style="margin-left:auto;display:flex;align-items:center;gap:4px;">
                ${menuBtn}
                <button id="svCloseBtn" style="background:none;border:none;color:#fff;font-size:22px;cursor:pointer;line-height:1;text-shadow:0 1px 4px rgba(0,0,0,.5);">×</button>
            </div>`;
        // Wire up listeners after innerHTML (CSP: no inline onclick)
        var svMenuBtnEl = document.getElementById('svMenuBtn');
        if (svMenuBtnEl) svMenuBtnEl.addEventListener('click', svToggleMenu);
        var svDeleteBtnEl = document.getElementById('svDeleteBtn');
        if (svDeleteBtnEl) svDeleteBtnEl.addEventListener('click', svDeleteStory);
        var svCloseBtnEl = document.getElementById('svCloseBtn');
        if (svCloseBtnEl) svCloseBtnEl.addEventListener('click', svClose);
    }

    async function svShowViewers() {
        const storyId = document.getElementById('svViewersBtn').dataset.storyId;
        if (!storyId) return;

        const modal = document.getElementById('storyViewersModal');
        const list  = document.getElementById('svViewersList');
        const title = document.getElementById('svViewersTitle');

        list.innerHTML = '<div style="padding:24px;text-align:center;color:#888;">Yükleniyor...</div>';
        title.textContent = 'Kim Gördü?';
        modal.style.display = 'flex';

        try {
            const data = await apiFetch(`/stories/${storyId}/viewers`);
            const viewers = data?.viewers ?? [];
            title.textContent = `Kim Gördü? (${viewers.length})`;

            if (!viewers.length) {
                list.innerHTML = '<div style="padding:24px;text-align:center;color:#888;">Henüz kimse görmedi</div>';
                return;
            }

            list.innerHTML = viewers.map(v => {
                const initial = (v.username ?? '?').charAt(0).toUpperCase();
                const timeAgo = _svFormatTime(v.viewed_at);
                return `
                    <div style="display:flex;align-items:center;padding:10px 20px;gap:12px;">
                        <div style="width:38px;height:38px;border-radius:50%;background:rgba(99,102,241,.15);display:flex;align-items:center;justify-content:center;font-weight:700;font-size:15px;color:var(--color-primary,#6366f1);flex-shrink:0;">${initial}</div>
                        <div style="flex:1;min-width:0;">
                            <div style="font-weight:600;font-size:14px;">${v.username}</div>
                            <div style="font-size:12px;color:#888;">${v.full_name}</div>
                        </div>
                        <div style="font-size:11px;color:#aaa;flex-shrink:0;">${timeAgo}</div>
                    </div>`;
            }).join('');
        } catch (err) {
            console.error('[StoryViewers] Yükleme başarısız:', err);
            if (window.Sentry) Sentry.captureException(err);
            list.innerHTML = '<div style="padding:24px;text-align:center;color:#e00;">Görüntüleyenler yüklenemedi</div>';
        }
    }

    function svToggleMenu(e) {
        e.stopPropagation();
        const dd = document.getElementById('svMenuDropdown');
        if (!dd) return;
        dd.style.display = dd.style.display === 'none' ? 'block' : 'none';
        // Dışarı tıklanınca kapat
        if (dd.style.display === 'block') {
            setTimeout(() => document.addEventListener('click', function _closeMenu() {
                dd.style.display = 'none';
                document.removeEventListener('click', _closeMenu);
            }), 0);
        }
    }

    async function svDeleteStory() {
        const group = _svGroups[_svGroupIdx];
        if (!group?.isMine) return;
        const mediaItems = (group.items ?? []).filter(i => i.story_type !== 'live_redirect');
        const item = mediaItems[_svItemIdx];
        if (!item?.id) return;

        const dd = document.getElementById('svMenuDropdown');
        if (dd) dd.style.display = 'none';

        // View isteğinin tamamlanması + video oynatmasının durması için videoyu durdur
        const video = document.getElementById('svVideo');
        if (video && !video.paused) video.pause();
        clearTimeout(_svTimer);
        cancelAnimationFrame(_svProgressAnim);
        // View isteği sunucuda işleniyorsa tamamlanması için kısa bekleme
        await new Promise(r => setTimeout(r, 300));

        if (!confirm('Bu hikayeyi silmek istediğine emin misin?')) {
            // İptal → videoyu sürdür
            if (video) video.play().catch(() => {});
            return;
        }

        try {
            await apiFetch(`/stories/${item.id}`, { method: 'DELETE' });
            // Silinen öğeyi state'den çıkar
            group.items = group.items.filter(i => i.id !== item.id);
            const remaining = group.items.filter(i => i.story_type !== 'live_redirect');
            if (remaining.length > 0) {
                // Sıradaki hikayeye geç (index taşmasını düzelt)
                if (_svItemIdx >= remaining.length) _svItemIdx = remaining.length - 1;
                svLoadItem();
            } else {
                // Hikaye kalmadı — viewer'ı kapat
                svClose();
            }
            loadFollowedStories(); // tray'i arka planda güncelle
        } catch(err) {
            // Story zaten silinmişse (expired veya önceden silindi) başarı say
            if (err?.error?.code === 'NOT_FOUND') {
                svClose();
                loadFollowedStories();
                return;
            }
            console.error('[Story] Hikaye silinemedi:', err);
            if (window.Sentry) Sentry.captureException(err);
            showAlert('Hikaye silinemedi.');
            if (video) video.play().catch(() => {});
        }
    }

    function _svFormatTime(isoStr) {
        if (!isoStr) return '';
        const diff = (Date.now() - new Date(isoStr).getTime()) / 1000;
        if (diff < 60) return 'Az önce';
        if (diff < 3600) return `${Math.floor(diff / 60)}d önce`;
        if (diff < 86400) return `${Math.floor(diff / 3600)}s önce`;
        return `${Math.floor(diff / 86400)}g önce`;
    }

    async function joinStream(id) {
        if (!Auth.getToken()) { window.location.href = '/giris.html'; return; }
        try {
            await Stream.joinStream(id);
            window.location.href = `/yayin.html?id=${id}`;
        } catch (err) { showAlert(err.error?.message || 'Yayına katılılamadı'); }
    }

    /* ── Story Upload: client-side validasyon + yükleme ─────────── */

    /**
     * HTML5 Video API ile süreyi tarayıcıda ölçer — sunucu hiç yorulmaz.
     * createObjectURL: dosyayı diske veya ağa atmadan bellek içi URL üretir.
     * onloadedmetadata: video.duration yalnızca başlık (ilk birkaç KB) okunduğunda
     * tetiklenir; videonun tamamı indirilmez.
     */
    function _getVideoDuration(file) {
        return new Promise((resolve, reject) => {
            const video = document.createElement('video');
            video.preload = 'metadata';
            video.onloadedmetadata = () => {
                URL.revokeObjectURL(video.src); // bellek serbest bırak
                resolve(video.duration);
            };
            video.onerror = () => {
                URL.revokeObjectURL(video.src);
                reject(new Error('Video okunamadı'));
            };
            video.src = URL.createObjectURL(file);
        });
    }

    function _setStoryUploading(active) {
        const btn   = document.getElementById('myStoryBtn');
        const inner = document.getElementById('myStoryInner');
        const badge = document.getElementById('myStoryBadge');
        if (!btn || !inner || !badge) return;

        if (active) {
            btn.classList.add('story-uploading');
            inner.innerHTML = '<div class="story-spinner"></div>';
            badge.style.display = 'none';
        } else {
            btn.classList.remove('story-uploading');
            badge.style.display = '';
        }
    }

    function setupStoryUpload() {
        const input = document.getElementById('storyUploadInput');
        if (!input) return;

        input.addEventListener('change', async () => {
            const file = input.files[0];
            if (!file) return;

            // ── 1. Boyut kontrolü (20 MB) ─────────────────────────
            const MAX_BYTES = 20 * 1024 * 1024;
            if (file.size > MAX_BYTES) {
                showAlert('Video boyutu 20 MB\'dan küçük olmalıdır.');
                input.value = '';
                return;
            }

            // ── 2. Süre kontrolü (≤ 15 sn + 1 sn tolerans) ────────
            let duration;
            try {
                duration = await _getVideoDuration(file);
            } catch (e) {
                showAlert('Video süresi ölçülemedi. Lütfen geçerli bir video seçin.');
                input.value = '';
                return;
            }

            if (duration > 16) {
                showAlert('Video en fazla 15 saniye olabilir.');
                input.value = '';
                return;
            }

            // ── 3. Yükleme (sıkıştırma sunucuda yapılır) ─────────
            _setStoryUploading(true);
            const token = Auth.getToken();
            const form  = new FormData();
            form.append('file', file);

            try {
                const res = await fetch('/api/stories/upload', {
                    method: 'POST',
                    headers: token ? { 'Authorization': `Bearer ${token}` } : {},
                    body: form,
                });

                if (!res.ok) {
                    const data = await res.json().catch(() => ({}));
                    throw new Error(data?.detail ?? `Sunucu hatası (${res.status})`);
                }

                input.value = '';
                await loadFollowedStories(); // tepsisi yenile
            } catch (err) {
                console.error('[StoryUpload] Yükleme başarısız:', err);
                if (window.Sentry) Sentry.captureException(err);
                showAlert(err.error?.message || err.message || 'Hikaye yüklenemedi. Lütfen tekrar deneyin.');
            } finally {
                _setStoryUploading(false);
            }
        });
    }

    /* ── İlanlar ────────────────────────────────────────────────── */
    let _allListings = [];
    let _filteredListings = [];
    let _listingsLoaded = false;
    let _activeCat = '';
    let _activeLocation = '';

    async function loadListings() {
        _listingsLoaded = true;
        try {
            const data = await apiFetch('/listings');
            _allListings = data;
            _applyFilters();
        } catch (_) {
            _allListings = [];
            _applyFilters();
        }
    }

    async function loadCityOptions() {
        try {
            const cities = await apiFetch('/cities');
            const sel = document.getElementById('locationFilter');
            cities.forEach(c => {
                const opt = document.createElement('option');
                opt.value = c;
                opt.textContent = c;
                sel.appendChild(opt);
            });
        } catch (_) { }
    }

    function _applyFilters() {
        const q = document.getElementById('listingSearch').value.trim().toLowerCase();
        _filteredListings = _allListings.filter(l =>
            (!_activeCat || l.category === _activeCat) &&
            (!_activeLocation || l.location === _activeLocation) &&
            (!q || l.title.toLowerCase().includes(q) || (l.description || '').toLowerCase().includes(q))
        );
        sortListings();
    }

    function filterCat(el, cat) {
        document.querySelectorAll('#listingCatBar .cat-pill').forEach(p => p.classList.remove('active'));
        el.classList.add('active');
        _activeCat = cat;
        _applyFilters();
    }

    function filterLocation() {
        _activeLocation = document.getElementById('locationFilter').value;
        _applyFilters();
    }

    function searchListings() {
        _applyFilters();
    }

    function sortListings() {
        const sort = document.getElementById('listingSort').value;
        if (sort === 'price_asc') _filteredListings.sort((a, b) => (a.price || 0) - (b.price || 0));
        else if (sort === 'price_desc') _filteredListings.sort((a, b) => (b.price || 0) - (a.price || 0));
        else _filteredListings.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
        renderListings();
    }


    let _listingView = localStorage.getItem('listingView') || 'grid';

    function setListingView(mode) {
        _listingView = mode;
        localStorage.setItem('listingView', mode);
        const list = document.getElementById('listingList');
        list.classList.toggle('view-grid', mode === 'grid');
        document.getElementById('btnViewList').classList.toggle('active', mode === 'list');
        document.getElementById('btnViewGrid').classList.toggle('active', mode === 'grid');
    }

    function renderListings() {
        const list = document.getElementById('listingList');
        const count = document.getElementById('listingCount');
        // Kayıtlı görünüm tercihini uygula
        list.classList.toggle('view-grid', _listingView === 'grid');
        document.getElementById('btnViewList').classList.toggle('active', _listingView === 'list');
        document.getElementById('btnViewGrid').classList.toggle('active', _listingView === 'grid');
        count.textContent = `${_filteredListings.length} ilan`;

        if (!_filteredListings.length) {
            list.innerHTML = `
                <div class="empty-state">
                    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                        <rect x="3" y="3" width="18" height="18" rx="2"/>
                        <path d="M3 9h18M9 21V9"/>
                    </svg>
                    <p>Bu kategoride ilan bulunamadı.</p>
                </div>`;
            return;
        }

        const _adCardHtml = `<div class="teqlif-ad-container">
            <div class="ad-badge">Sponsorlu</div>
            <ins class="adsbygoogle"
                 style="display:block"
                 data-ad-format="fluid"
                 data-ad-layout-key="-fb+5w+4e-db+86"
                 data-ad-client="ca-pub-2403555634390058"
                 data-ad-slot="otomatik_reklam_alani"></ins>
        </div>`;

        list.innerHTML = _filteredListings.map((l, idx) => {
            const ad = (idx > 0 && idx % 5 === 0) ? _adCardHtml : '';
            return ad + `
            <div class="listing-item" data-listing-id="${l.id}" style="cursor:pointer">
                <div class="listing-img" style="position:relative;">
                    ${l.image_url
                ? `<img src="${escHtml(l.image_url)}" style="width:100%;height:100%;object-fit:cover;">`
                : `<svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>`
            }
                    <button class="tile-like-chip" id="like-listing-${l.id}"
                            data-like-listing="${l.id}"
                            title="Beğen">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="${l.is_liked ? '#ef4444' : 'none'}"
                             stroke="${l.is_liked ? '#ef4444' : '#fff'}" stroke-width="2.2">
                            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>
                        </svg>
                        <span id="like-count-listing-${l.id}">${(l.likes_count || 0) > 0 ? (l.likes_count) : ''}</span>
                    </button>
                </div>
                <div class="listing-body">
                    <div>
                        <div class="listing-item-title">${escHtml(l.title)}</div>
                        <div class="listing-item-desc">${escHtml(l.description || '')}</div>
                    </div>
                    <div class="listing-item-meta">
                        <span class="listing-item-price">${l.price ? l.price.toLocaleString('tr-TR') + ' ₺' : 'Fiyat belirtilmemiş'}</span>
                        <span class="listing-item-info">${escHtml(l.location || '')} · ${formatDate(l.created_at)}</span>
                    </div>
                </div>
            </div>`;
        }).join('');
        // Yeni eklenen adsbygoogle ins elementlerini başlat
        (window.adsbygoogle = window.adsbygoogle || []).push({});
        _rebuildListingMap();
    }

    function formatDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        const diff = (Date.now() - d) / 1000;
        if (diff < 3600) return Math.floor(diff / 60) + ' dk önce';
        if (diff < 86400) return Math.floor(diff / 3600) + ' sa önce';
        return Math.floor(diff / 86400) + ' gün önce';
    }

    /* ── İlan Beğeni Toggle (Optimistic UI) ────────────────────────── */
    // Listing nesneleri _filteredListings içinde tutulur; id → nesne haritası
    const _listingMap = {};
    // _filteredListings değiştiğinde map'i güncelle (renderListings sonrasında çağrılır)
    function _rebuildListingMap() {
        (_filteredListings || []).forEach(l => { _listingMap[l.id] = l; });
    }

    async function toggleListingLike(id) {
        if (!Auth.getToken()) { window.location.href = '/giris.html?next=/'; return; }
        const l = _listingMap[id];
        if (!l) return;
        // Optimistic
        const prevLiked = l.is_liked;
        const prevCount = l.likes_count || 0;
        l.is_liked = !l.is_liked;
        l.likes_count = prevCount + (l.is_liked ? 1 : -1);
        _applyListingLikeUI(id, l.is_liked, l.likes_count);
        try {
            const res = await apiFetch(`/listings/${id}/like`, { method: 'POST' });
            if (res) { l.is_liked = res.is_liked; l.likes_count = res.likes_count; }
            _applyListingLikeUI(id, l.is_liked, l.likes_count);
        } catch (_) {
            // Geri al
            l.is_liked = prevLiked; l.likes_count = prevCount;
            _applyListingLikeUI(id, prevLiked, prevCount);
        }
    }

    function _applyListingLikeUI(id, liked, count) {
        const btn = document.getElementById(`like-listing-${id}`);
        const countEl = document.getElementById(`like-count-listing-${id}`);
        if (!btn) return;
        const svg = btn.querySelector('svg');
        if (svg) {
            svg.setAttribute('fill', liked ? '#ef4444' : 'none');
            svg.setAttribute('stroke', liked ? '#ef4444' : '#fff');
        }
        if (countEl) countEl.textContent = count > 0 ? count : '';
    }

    /* ── Yardımcılar ────────────────────────────────────────────── */
    function escHtml(str) {
        if (!str) return '';
        return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function showAlert(msg) {
        alertEl.textContent = msg;
        alertEl.style.display = 'block';
        setTimeout(() => alertEl.style.display = 'none', 4000);
    }

    /* ── Yayın başlat modal ─────────────────────────────────────── */
    btnYayınAc.addEventListener('click', () => {
        if (!Auth.getToken()) {
            window.location.href = '/giris.html?next=/';
            return;
        }
        startModal.classList.add('open');
        document.getElementById('streamTitle').focus();
    });
    document.getElementById('btnCancelModal').addEventListener('click', () => {
        startModal.classList.remove('open');
    });
    startModal.addEventListener('click', e => {
        if (e.target === startModal) startModal.classList.remove('open');
    });
    document.getElementById('btnConfirmStart').addEventListener('click', async () => {
        const title = document.getElementById('streamTitle').value.trim();
        const category = document.getElementById('streamCategory').value;
        if (!title) {
            modalAlert.textContent = 'Yayın başlığı zorunludur';
            modalAlert.style.display = 'block';
            return;
        }
        if (!category) {
            modalAlert.textContent = 'Kategori seçimi zorunludur';
            modalAlert.style.display = 'block';
            return;
        }
        modalAlert.style.display = 'none';
        const btn = document.getElementById('btnConfirmStart');
        const startingOverlay = document.getElementById('streamStartingOverlay');
        btn.disabled = true;
        startModal.classList.remove('open');
        startingOverlay.classList.add('visible');
        try {
            const data = await Stream.startStream(title, category);
            window.location.href = `/yayin.html?id=${data.stream_id}&host=1`;
        } catch (err) {
            startingOverlay.classList.remove('visible');
            startModal.classList.add('open');
            btn.disabled = false;
            const errCode = err?.error?.code;
            if (errCode === 'RATE_LIMIT_EXCEEDED') {
                modalAlert.textContent = 'Çok hızlı işlem yapıyorsunuz. Lütfen biraz bekleyin.';
            } else if (errCode === 'FORBIDDEN' || (err?.error?.status === 403)) {
                modalAlert.textContent = 'Güvenlik doğrulaması başarısız. Lütfen tekrar deneyin.';
            } else {
                modalAlert.textContent = err?.error?.message || 'Yayın başlatılamadı';
            }
            modalAlert.style.display = 'block';
            console.error('[LiveStart] Yayın başlatma hatası:', err);
            if (window.Sentry) { Sentry.captureException(err); }
        }
    });

    loadStreams();
    loadFollowedStories();
    setupStoryUpload();

// ── Inline handler'lardan taşınan event listener'lar ─────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    var tabCanli = document.getElementById('tab-canli');
    if (tabCanli) tabCanli.addEventListener('click', function () { switchTab('canli'); });

    var tabIlanlar = document.getElementById('tab-ilanlar');
    if (tabIlanlar) tabIlanlar.addEventListener('click', function () { switchTab('ilanlar'); });

    // Sayfa yüklendiğinde URL'de hash varsa, İlanlar sekmesini otomatik aç (`history.back` senaryosu)
    if (window.location.hash === '#ilanlar') {
        switchTab('ilanlar');
    }

    var svTapLeft = document.getElementById('svTapLeft');
    if (svTapLeft) {
        svTapLeft.addEventListener('click', function () { svNavigate(-1); });
        svTapLeft.addEventListener('dblclick', svTriggerHeart);
    }
    var svTapRight = document.getElementById('svTapRight');
    if (svTapRight) {
        svTapRight.addEventListener('click', function () { svNavigate(1); });
        svTapRight.addEventListener('dblclick', svTriggerHeart);
    }

    var svShowViewersBtn = document.getElementById('svShowViewersBtn');
    if (svShowViewersBtn) svShowViewersBtn.addEventListener('click', svShowViewers);

    var svLikeHeart = document.getElementById('svLikeHeart');
    if (svLikeHeart) svLikeHeart.addEventListener('click', svToggleLike);

    var svViewersCloseBtn = document.getElementById('svViewersCloseBtn');
    if (svViewersCloseBtn) svViewersCloseBtn.addEventListener('click', function () {
        var m = document.getElementById('storyViewersModal');
        if (m) m.style.display = 'none';
    });

    // Stream cards — event delegation (CSP: no inline onclick)
    var streamsGrid = document.getElementById('streamsGrid');
    if (streamsGrid) streamsGrid.addEventListener('click', function (e) {
        // "Katıl" button
        var joinBtn = e.target.closest('[data-join-stream]');
        if (joinBtn) { e.stopPropagation(); joinStream(Number(joinBtn.dataset.joinStream)); return; }
        // Profile link — let it navigate normally
        if (e.target.closest('[data-stop-propagation]')) return;
        // Card click
        var card = e.target.closest('[data-stream-id]');
        if (card) joinStream(Number(card.dataset.streamId));
    });

    // Listing items — event delegation (CSP: no inline onclick)
    var listingList = document.getElementById('listingList');
    if (listingList) listingList.addEventListener('click', function (e) {
        // Like button
        var likeBtn = e.target.closest('[data-like-listing]');
        if (likeBtn) { e.stopPropagation(); toggleListingLike(Number(likeBtn.dataset.likeListing), likeBtn); return; }
        // Listing card
        var item = e.target.closest('[data-listing-id]');
        if (item) window.location.href = '/ilan/' + item.dataset.listingId;
    });

    // Story tray — event delegation (CSP: no inline onclick)
    var storyTray = document.getElementById('storyTray');
    if (storyTray) storyTray.addEventListener('click', function (e) {
        var target = e.target.closest('[data-story-action],[data-story-stream],[data-story-group]');
        if (!target) return;
        if (target.dataset.stopPropagation) e.stopPropagation();
        var action = target.dataset.storyAction;
        if (action === 'open-mine') { svOpenMine(); return; }
        if (action === 'upload') { document.getElementById('storyUploadInput').click(); return; }
        if (target.dataset.storyStream) { joinStream(Number(target.dataset.storyStream)); return; }
        if (target.dataset.storyGroup !== undefined) { svOpenGroup(Number(target.dataset.storyGroup)); return; }
    });

    // Stream category pills — event delegation
    var streamCatBar = document.getElementById('streamCatBar');
    if (streamCatBar) streamCatBar.addEventListener('click', function (e) {
        var pill = e.target.closest('.cat-pill');
        if (pill) filterStreamCat(pill, pill.dataset.cat || '');
    });

    var btnSearchListings = document.getElementById('btnSearchListings');
    if (btnSearchListings) btnSearchListings.addEventListener('click', searchListings);

    // Listing category pills — event delegation
    var listingCatBar = document.getElementById('listingCatBar');
    if (listingCatBar) listingCatBar.addEventListener('click', function (e) {
        var pill = e.target.closest('.cat-pill');
        if (pill) filterCat(pill, pill.dataset.cat || '');
    });

    var locationFilter = document.getElementById('locationFilter');
    if (locationFilter) locationFilter.addEventListener('change', filterLocation);

    var listingSort = document.getElementById('listingSort');
    if (listingSort) listingSort.addEventListener('change', sortListings);

    var btnViewList = document.getElementById('btnViewList');
    if (btnViewList) btnViewList.addEventListener('click', function () { setListingView('list'); });

    var btnViewGrid = document.getElementById('btnViewGrid');
    if (btnViewGrid) btnViewGrid.addEventListener('click', function () { setListingView('grid'); });
});
