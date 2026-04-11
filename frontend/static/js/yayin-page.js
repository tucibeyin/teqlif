    const streamIdParam = parseInt(params.get('id'));
    const isHostParam = params.get('host') === '1';

    const mainVideo = document.getElementById('mainVideo');
    const remoteAudio = document.getElementById('remoteAudio');
    const connectingOverlay = document.getElementById('connectingOverlay');
    const videoPlaceholder = document.getElementById('videoPlaceholder');
    const videoOverlay = document.getElementById('videoOverlay');
    const streamMeta = document.getElementById('streamMeta');
    const statusMsg = document.getElementById('statusMsg');
    const viewerCount = document.getElementById('viewerCount');
    let micEnabled = true;
    let streamId = null;

    function setStatus(msg, isError = false) {
        statusMsg.textContent = msg;
        statusMsg.className = isError ? 'error' : '';
    }

    function showVideo() {
        connectingOverlay.style.display = 'none';
        videoPlaceholder.style.display = 'none';
        mainVideo.style.display = 'block';
        videoOverlay.style.display = 'flex';
        streamMeta.style.display = 'flex';
    }

    function showPlaceholder(text) {
        connectingOverlay.style.display = 'none';
        videoPlaceholder.style.display = 'flex';
        document.getElementById('placeholderText').textContent = text;
        videoOverlay.style.display = 'flex';
        streamMeta.style.display = 'flex';
    }

    async function init() {
        if (!Auth.getToken()) {
            window.location.href = '/giris.html';
            return;
        }

        const info = Stream.load();

        // Session'da bilgi yoksa ya da ID uyuşmuyorsa
        if (!info || (streamIdParam && info.stream_id !== streamIdParam)) {
            setStatus('Oturum bilgisi bulunamadı. Yeniden yönlendiriliyor...', true);
            setTimeout(() => window.location.href = '/', 2000);
            return;
        }

        streamId = info.stream_id;
        const isHost = info.is_host;

        // Meta bilgileri göster
        document.getElementById('metaTitle').textContent = info.title || 'Canlı Yayın';
        if (!isHost && info.host_username) {
            document.getElementById('metaHost').textContent = `@${info.host_username} yayın yapıyor`;
        } else {
            document.getElementById('metaHost').textContent = 'Siz yayın yapıyorsunuz';
        }

        if (isHost) {
            document.getElementById('btnEndStream').style.display = '';
            document.getElementById('btnToggleMic').style.display = '';
            document.getElementById('btnToggleCamera').style.display = '';
            // Birden fazla kamera varsa "Değiştir" butonunu göster
            navigator.mediaDevices.enumerateDevices().then(devices => {
                const cams = devices.filter(d => d.kind === 'videoinput');
                if (cams.length > 1) document.getElementById('btnSwitchCamera').style.display = '';
            }).catch(() => {});
        } else {
            document.getElementById('btnLeave').style.display = '';
            // Kalp butonu sadece izleyicide görünür
            const _hBtn = document.getElementById('streamHeartBtn');
            if (_hBtn) _hBtn.style.display = 'flex';
            // mainVideo daima muted — ses remoteAudio elementi üzerinden çıkar
        }

        let videoStarted = false;
        try {
            const room = await connectRoom({
                livekit_url: info.livekit_url,
                token: info.token,
                isHost,
                hostIdentity: isHost ? null : (info.host_livekit_identity || null),
                localVideoEl: isHost ? mainVideo : null,
                remoteVideoEl: isHost ? null : mainVideo,
                remoteAudioEl: isHost ? null : remoteAudio,
                onDisconnect: () => {
                    if (!isHost && !_isSelfCoHost) {
                        _onStreamEndedViewer();
                    }
                },
                onRemoteVideo: () => {
                    videoStarted = true;
                    showVideo();
                    setStatus('');
                },
                onCoHostPip: isHost ? (pipEl) => _addHostRemoveBtn(pipEl) : null,
            });

            if (isHost) {
                showVideo();
                setStatus('Yayın canlı. İzleyiciler sizi görebilir.');
                _scheduleThumbCapture(streamId);
                _initViewerPopup(streamId);
            } else if (!videoStarted) {
                // Video henüz gelmediyse placeholder göster (onRemoteVideo gelince kapanır)
                showPlaceholder('Yayına bağlanıldı, video bekleniyor...');
            }

            document.getElementById('viewerCountText').textContent = `👁 ${info.viewer_count ?? 0}`;

            // Açık artırmayı başlat
            initAuction(streamId, isHost);

            // Sohbeti başlat
            initChat(streamId, isHost);

        } catch (err) {
            console.error(err);
            setStatus('Bağlantı kurulamadı: ' + (err.error?.message || err.message || 'Bilinmeyen hata'), true);
            connectingOverlay.innerHTML = `<span style="color:#f87171">Bağlantı hatası</span>`;
        }
    }

    // ── Viewer listesi popup (sadece host) ────────────────────────────
    function _initViewerPopup(streamId) {
        const badge = document.getElementById('viewerCount');
        const popup = document.getElementById('viewerPopup');
        if (!badge || !popup) return;
        badge.classList.add('host-clickable');

        badge.addEventListener('click', async (e) => {
            e.stopPropagation();
            const isOpen = popup.classList.contains('open');
            if (isOpen) { popup.classList.remove('open'); return; }
            popup.innerHTML = '<div class="viewer-popup-empty">Yükleniyor...</div>';
            popup.classList.add('open');
            try {
                const token = Auth.getToken();
                const res = await fetch(`/api/streams/${streamId}/viewers`, {
                    headers: { 'Authorization': `Bearer ${token}` }
                });
                const data = await res.json();
                const viewers = data.viewers || [];
                if (viewers.length === 0) {
                    popup.innerHTML = '<div class="viewer-popup-empty">Henüz izleyici yok</div>';
                } else {
                    popup.innerHTML = viewers.map(u =>
                        `<div class="viewer-popup-item">@${u}</div>`
                    ).join('');
                }
            } catch (_) {
                popup.innerHTML = '<div class="viewer-popup-empty">Yüklenemedi</div>';
            }
        });

        document.addEventListener('click', () => popup.classList.remove('open'));
    }

    // ── Otomatik kapak fotoğrafı (host) ────────────────────────────────
    let _thumbInterval = null;

    async function _captureAndUploadThumb(sid) {
        const video = document.getElementById('mainVideo');
        if (!video || video.readyState < 2 || video.videoWidth === 0) return;
        try {
            const canvas = document.createElement('canvas');
            canvas.width = Math.round(video.videoWidth / 2);
            canvas.height = Math.round(video.videoHeight / 2);
            canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
            const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.8));
            if (!blob) return;
            const form = new FormData();
            form.append('file', blob, 'thumb.jpg');
            const token = Auth.getToken();
            await fetch(`/api/streams/${sid}/thumbnail`, {
                method: 'PATCH',
                headers: token ? { 'Authorization': 'Bearer ' + token } : {},
                body: form,
            });
        } catch (e) { /* sessiz geç */ }
    }

    function _scheduleThumbCapture(sid) {
        setTimeout(async () => {
            await _captureAndUploadThumb(sid);
            _thumbInterval = setInterval(() => _captureAndUploadThumb(sid), 60000);
        }, 5000);
    }

    // Yayını Bitir (Host)
    document.getElementById('btnEndStream').addEventListener('click', async () => {
        const btn = document.getElementById('btnEndStream');
        btn.disabled = true;
        btn.textContent = 'Bitiriliyor...';
        clearInterval(_thumbInterval);
        try {
            await Stream.endStream(streamId);
        } catch (_) { }
        Chat.disconnect();
        await disconnectRoom();
        Stream.clear();
        window.location.href = '/';
    });

    // Mikrofon Kapat/Aç (Host)
    document.getElementById('btnToggleMic').addEventListener('click', async () => {
        const btn = document.getElementById('btnToggleMic');
        micEnabled = !micEnabled;
        if (_room) {
            await _room.localParticipant.setMicrophoneEnabled(micEnabled);
        }
        btn.textContent = micEnabled ? '🎙 Mikrofon Kapat' : '🔇 Mikrofon Aç';
    });

    // Kamera Kapat/Aç (Host)
    let cameraEnabled = true;
    document.getElementById('btnToggleCamera').addEventListener('click', async () => {
        const btn = document.getElementById('btnToggleCamera');
        cameraEnabled = !cameraEnabled;
        if (_room) {
            await _room.localParticipant.setCameraEnabled(cameraEnabled);
        }
        btn.textContent = cameraEnabled ? '📷 Kamera Kapat' : '📷 Kamera Aç';
    });

    // Kamera Değiştir (Host — birden fazla kamera varsa)
    document.getElementById('btnSwitchCamera').addEventListener('click', async () => {
        const btn = document.getElementById('btnSwitchCamera');
        if (!_room) return;
        try {
            btn.disabled = true;
            const devices = await navigator.mediaDevices.enumerateDevices();
            const cams = devices.filter(d => d.kind === 'videoinput');
            if (cams.length < 2) return;
            const currentId = _room.localParticipant.videoTrackPublications.values().next()
                ?.value?.track?.mediaStreamTrack?.getSettings()?.deviceId;
            const currentIdx = cams.findIndex(d => d.deviceId === currentId);
            const nextCam = cams[(currentIdx + 1) % cams.length];
            await _room.switchActiveDevice('videoinput', nextCam.deviceId);
        } catch (e) {
            console.error('Kamera değiştirilemedi:', e);
        } finally {
            btn.disabled = false;
        }
    });

    // Yayın sona erdi — viewer tam sayfa bildirim + yönlendirme
    let _streamEndedHandled = false;
    function _onStreamEndedViewer() {
        if (_streamEndedHandled) return;
        _streamEndedHandled = true;
        Chat.disconnect();
        const el = document.createElement('div');
        el.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.92);z-index:9999;display:flex;align-items:center;justify-content:center;';
        el.innerHTML = `
            <div style="text-align:center;color:#fff;padding:2rem;">
                <div style="font-size:3.5rem;margin-bottom:1rem;">📺</div>
                <div style="font-size:1.3rem;font-weight:700;margin-bottom:0.5rem;">Yayın Sona Erdi</div>
                <div style="color:#94a3b8;margin-bottom:1.5rem;">Bu yayın yayıncı tarafından sonlandırıldı.</div>
                <div style="color:#64748b;font-size:0.85rem;">Canlı yayınlara yönlendiriliyorsunuz...</div>
            </div>`;
        document.body.appendChild(el);
        setTimeout(() => { window.location.href = '/'; }, 3000);
    }

    // Ayrıl (Viewer)
    document.getElementById('btnLeave').addEventListener('click', async () => {
        const btn = document.getElementById('btnLeave');
        btn.disabled = true;
        btn.textContent = 'Ayrılıyor...';
        try {
            await Stream.leaveStream(streamId);
        } catch (_) { }
        Chat.disconnect();
        await disconnectRoom();
        Stream.clear();
        window.location.href = '/';
    });

    // ── Açık Artırma ────────────────────────────────────────────────

    let _currentAuctionStatus = 'idle';
    let _currentBid = 0;
    let _currentBidder = null;
    let _currentItemName = null;
    let _iAmLeadingBidder = false; // En yüksek teklif bende → bitiş konfetisi için
    let _currentListingId = null;  // viewer için pinlenmiş ilan
    let _selectedListingId = null; // host için seçilen ilan
    let _listingMode = false;      // host: listing mi manual mı
    let _lastBidCount = 0;         // teklif sayısı takibi
    let _currentGroupEl = null;    // aktif artırma bid-group-items konteyneri
    let _currentBinPrice = null;   // buy_it_now_price
    let _isBoughtItNow = false;    // son artırma Hemen Al ile mi kapandı
    let _quickAuctionCount = 0;    // hızlı açık artırma sayacı (Ürün 1, 2, 3...)

    // chat.js ile aynı palet ve algoritma — bağımsız çalışır
    const _USER_PALETTE = [
        '#f87171', '#fb923c', '#fbbf24', '#a3e635',
        '#4ade80', '#2dd4bf', '#22d3ee', '#38bdf8',
        '#818cf8', '#c084fc', '#f472b6', '#fb7185',
    ];
    function _usernameColor(username) {
        let hash = 0;
        for (let i = 0; i < username.length; i++) {
            hash = (hash * 31 + username.charCodeAt(i)) & 0x7fffffff;
        }
        return _USER_PALETTE[hash % _USER_PALETTE.length];
    }

    function _addBidEntry(username, amount) {
        const list = document.getElementById('bidsList');
        if (!list) return;
        const empty = document.getElementById('bidsEmpty');
        if (empty) empty.remove();
        // Grup yoksa doğrudan listeye ekle (eski davranış — fallback)
        const container = _currentGroupEl || list;
        // Mevcut grup içindeki sıra numaralarını güncelle
        container.querySelectorAll('.bid-rank').forEach((el, i) => {
            el.textContent = `#${i + 2}`;
            el.classList.remove('first');
        });
        const u = username.replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const color = _usernameColor(username);
        const div = document.createElement('div');
        div.className = 'bid-item';
        div.innerHTML = `<span class="bid-rank first">#1</span><span class="bid-user${_isHostPage ? ' clickable' : ''}" data-username="${u}" style="color:${color}">@${u}</span><span class="bid-amount">₺${Number(amount).toLocaleString('tr-TR')}</span>`;
        container.insertBefore(div, container.firstChild);
    }

    function _startBidGroup(itemName) {
        const list = document.getElementById('bidsList');
        if (!list) return;
        const empty = document.getElementById('bidsEmpty');
        if (empty) empty.remove();
        // Önceki aktif grubu passive yap
        list.querySelectorAll('.bid-group.active').forEach(g => g.classList.remove('active'));
        const group = document.createElement('div');
        group.className = 'bid-group active';
        const header = document.createElement('div');
        header.className = 'bid-group-header';
        header.textContent = itemName || 'Açık Artırma';
        const items = document.createElement('div');
        items.className = 'bid-group-items';
        group.appendChild(header);
        group.appendChild(items);
        list.prepend(group);
        list.scrollTop = 0;
        _currentGroupEl = items;
    }

    function _clearBidsList() {
        const list = document.getElementById('bidsList');
        if (!list) return;
        list.innerHTML = '<div class="bids-empty" id="bidsEmpty">Henüz teklif yok.</div>';
        _currentGroupEl = null;
    }

    function updateAuctionUI(msg) {
        if (msg.type === 'buy_it_now_requested') {
            if (_isHostPage) {
                _showBuyItNowRequestModal(
                    msg.buyer?.username || '?',
                    msg.price,
                    msg.item_name || _currentItemName || ''
                );
            } else if (_iAmBinBuyer) {
                // Sadece BIN talebini başlatan viewer — bekleme mesajı
                const binBtn = document.getElementById('btnBuyItNow');
                if (binBtn) binBtn.style.display = 'none';
                setAuctionMsg('⚡ Talebiniz iletildi, host onayı bekleniyor...', '');
            } else {
                // Diğer viewer'lar — teklif alanı devre dışı + bilgi mesajı
                const binBtn = document.getElementById('btnBuyItNow');
                if (binBtn) binBtn.style.display = 'none';
                const bidInput = document.getElementById('bidInput');
                if (bidInput) bidInput.disabled = true;
                const btnPlaceBid = document.getElementById('btnPlaceBid');
                if (btnPlaceBid) btnPlaceBid.disabled = true;
                setAuctionMsg('⏳ Başka bir kullanıcı ile Hemen Al işlemi yapılıyor.', '');
            }
            return;
        }

        if (msg.type === 'buy_it_now_rejected') {
            if (!_isHostPage) {
                if (_iAmBinBuyer) {
                    // Teklif veren viewer: modal'ı kapat, red mesajı göster
                    _closeBuyItNowModal(); // _iAmBinBuyer'ı da false yapar
                    setAuctionMsg('Hemen Al talebiniz reddedildi, artırma devam ediyor.', 'error');
                } else {
                    // Diğer viewer'lar: teklif alanını geri aç
                    const bidInput = document.getElementById('bidInput');
                    if (bidInput) bidInput.disabled = false;
                    const btnPlaceBid = document.getElementById('btnPlaceBid');
                    if (btnPlaceBid) btnPlaceBid.disabled = false;
                    setAuctionMsg('Hemen Al işlemi reddedildi, artırma devam ediyor.', '');
                }
                setTimeout(() => setAuctionMsg('', ''), 4000);
            }
            return;
        }

        // auction_ended_by_buy_it_now event'i — özel SATILDI overlay
        if (msg.type === 'auction_ended_by_buy_it_now') {
            const wasBuyer = _iAmBinBuyer; // close öncesi kaydet
            _closeBuyItNowModal(); // onay verildi, bekleme modalını kapat + _iAmBinBuyer sıfırla
            _isBoughtItNow = true;
            const buyer = msg.buyer?.username || '?';
            const price = msg.price != null ? '₺' + Number(msg.price).toLocaleString('tr-TR') : '';
            const itemName = msg.item_name || _currentItemName || '';
            _showSoldBanner(buyer, price, itemName);
            // viewerControls'u gizle, Hemen Al butonunu kapat
            const vc = document.getElementById('viewerControls');
            if (vc) vc.style.display = 'none';
            const binBtn = document.getElementById('btnBuyItNow');
            if (binBtn) binBtn.style.display = 'none';
            // Bilgilendirme mesajı: rol bazlı
            if (_isHostPage) {
                setAuctionMsg(`🛒 Hemen Al tamamlandı! @${buyer}${price ? ' — ' + price : ''}`, 'success');
            } else if (wasBuyer) {
                setAuctionMsg('🎉 Tebrikler! Satın alma tamamlandı.', 'success');
                Auction.fireWinnerConfetti();
            } else {
                setAuctionMsg(`🛒 Ürün Hemen Satıldı! @${buyer}${price ? ' — ' + price : ''}`, '');
            }
            return;
        }

        const state = msg; // type === 'state' — normal alanlar mevcut
        const _prevAuctionStatus = _currentAuctionStatus;
        _currentAuctionStatus = state.status;
        _currentListingId = state.listing_id || null;
        _currentBidder = state.current_bidder || null;
        _currentItemName = state.item_name || null;
        _currentBinPrice = state.buy_it_now_price ?? null;
        // Her zaman güncel bid'i al; null ise sıfırla (yeni artırma başlangıcı)
        _currentBid = state.current_bid ?? 0;

        // idle VEYA active'e geçişte buy-it-now bayrağını sıfırla.
        // Buy-it-now sonrası yeni artırma idle'dan geçmeden doğrudan active gelir.
        if (state.status === 'idle') {
            _isBoughtItNow = false;
            _iAmLeadingBidder = false;
            _hideSoldBanner();
        }
        if (state.status === 'active') {
            _isBoughtItNow = false;
            _hideSoldBanner();
            // En yüksek teklif bende mi? — ended'te konfeti için takip et
            const _me = Auth.getUser()?.username;
            _iAmLeadingBidder = !!(_me && state.current_bidder && state.current_bidder === _me);
        }

        // Normal bitiş konfetisi: leading bidder idiysen patlat
        if (state.status === 'ended' && _prevAuctionStatus !== 'ended' && !_isBoughtItNow) {
            const _meNow = Auth.getUser()?.username;
            // İkili kontrol: flag (active'de takip) VEYA direkt ended state karşılaştırması
            const _isWinner = _iAmLeadingBidder ||
                !!(_meNow && state.current_bidder && state.current_bidder === _meNow);
            console.log('[Auction] Bitiş tespiti:', {
                winner: state.current_bidder,
                me: _meNow,
                iAmLeading: _iAmLeadingBidder,
                isWinner: _isWinner,
                confettiAvailable: typeof confetti === 'function',
            });
            if (_isWinner) {
                Auction.fireWinnerConfetti();
            }
            _iAmLeadingBidder = false;
        }

        const panel = document.getElementById('auctionPanel');
        const badge = document.getElementById('auctionBadge');
        const bidInfo = document.getElementById('auctionBidInfo');
        const hostSetup = document.getElementById('hostSetup');
        const hostControls = document.getElementById('hostControls');
        const viewerControls = document.getElementById('viewerControls');

        panel.classList.add('visible');

        // Badge: isBoughtItNow && ended → SATILDI rozeti
        if (_isBoughtItNow && state.status === 'ended') {
            badge.textContent = 'SATILDI 🛒';
            badge.className = 'auction-status-badge badge-sold';
        } else if (state.status === 'buy_it_now_pending') {
            badge.textContent = Auction.STATUS_LABELS[state.status] || state.status;
            badge.className = 'auction-status-badge badge-pending';
        } else {
            badge.textContent = Auction.STATUS_LABELS[state.status] || state.status;
            badge.className = 'auction-status-badge badge-' + state.status;
        }

        if (state.item_name) document.getElementById('auctionItemName').textContent = state.item_name;

        if (state.current_bid != null) {
            _currentBid = state.current_bid;
            document.getElementById('auctionPrice').textContent = '₺' + Number(state.current_bid).toLocaleString('tr-TR');
            document.getElementById('auctionBidder').textContent = state.current_bidder
                ? `@${state.current_bidder} en yüksek teklif sahibi`
                : (state.start_price != null ? `Başlangıç: ₺${Number(state.start_price).toLocaleString('tr-TR')}` : '');
            document.getElementById('auctionBidCount').textContent = state.bid_count > 0 ? `${state.bid_count} teklif` : '';
            bidInfo.style.display = 'block';
        }

        // BIN badge güncelle (hem host hem viewer için göster)
        const binBadge = document.getElementById('auctionBinBadge');
        if (binBadge) {
            if (_currentBinPrice != null && state.status === 'active') {
                binBadge.textContent = `⚡ ${Number(_currentBinPrice).toLocaleString('tr-TR')} ₺`;
                binBadge.style.display = '';
            } else {
                binBadge.style.display = 'none';
            }
        }

        // Teklif listesi güncelle
        const newBidCount = state.bid_count || 0;
        if (state.status === 'idle' || state.status === 'ended') {
            // Artırma kapandı — grubu pasife al, pointer'ı sıfırla
            if (_currentGroupEl) {
                _currentGroupEl.closest('.bid-group')?.classList.remove('active');
                _currentGroupEl = null;
            }
            _lastBidCount = 0;
        } else {
            // → active geçişinde yeni grup başlat
            if (state.status === 'active' && _currentGroupEl === null) {
                _startBidGroup(state.item_name || _currentItemName || 'Açık Artırma');
            }
            if (newBidCount > _lastBidCount && state.current_bidder && state.current_bid != null) {
                _addBidEntry(state.current_bidder, state.current_bid);
            }
            _lastBidCount = newBidCount;
        }

        // Viewer: pinlenmiş ilan butonu
        const listingBtn = document.getElementById('auctionListingBtn');
        if (listingBtn) {
            listingBtn.style.display = (!_isHostPage && _currentListingId && state.status !== 'idle') ? '' : 'none';
        }

        const isHost = document.getElementById('hostSetup') !== null && (_isHostPage || _isCoHost);

        if (isHost) {
            hostControls.style.display = 'flex';
            if (state.status === 'idle' || state.status === 'ended') {
                hostSetup.style.display = 'flex';
                document.getElementById('btnAuctionQuickStart').style.display = '';
                document.getElementById('btnAuctionStart').style.display = '';
                document.getElementById('btnAuctionPause').style.display = 'none';
                document.getElementById('btnAuctionResume').style.display = 'none';
                document.getElementById('btnAuctionAccept').style.display = 'none';
                document.getElementById('btnAuctionEnd').style.display = 'none';
                // ended sonrası listing seçimini ve BIN inputu sıfırla
                if (state.status === 'ended') _resetListingMode();
            } else if (state.status === 'active') {
                hostSetup.style.display = 'none';
                document.getElementById('btnAuctionQuickStart').style.display = 'none';
                document.getElementById('btnAuctionStart').style.display = 'none';
                document.getElementById('btnAuctionPause').style.display = '';
                document.getElementById('btnAuctionResume').style.display = 'none';
                document.getElementById('btnAuctionAccept').style.display = state.current_bidder ? '' : 'none';
                document.getElementById('btnAuctionEnd').style.display = '';
            } else if (state.status === 'paused') {
                hostSetup.style.display = 'none';
                document.getElementById('btnAuctionQuickStart').style.display = 'none';
                document.getElementById('btnAuctionStart').style.display = 'none';
                document.getElementById('btnAuctionPause').style.display = 'none';
                document.getElementById('btnAuctionResume').style.display = '';
                document.getElementById('btnAuctionAccept').style.display = state.current_bidder ? '' : 'none';
                document.getElementById('btnAuctionEnd').style.display = '';
            }
        } else if (viewerControls) {
            const showViewer = state.status === 'active' && !_isBoughtItNow;
            viewerControls.style.display = showViewer ? 'flex' : 'none';

            // Başka kullanıcı BIN işlemi yapıyorsa diğer viewer'lara bilgi ver
            if (state.status === 'buy_it_now_pending' && !_iAmBinBuyer) {
                setAuctionMsg('⏳ Başka bir kullanıcı ile Hemen Al işlemi yapılıyor.', '');
            }

            // Hemen Al butonu: BIN varsa ve currentBid < BIN ise göster
            const binBtn = document.getElementById('btnBuyItNow');
            if (binBtn) {
                const binVisible = showViewer &&
                    _currentBinPrice != null &&
                    (_currentBid == null || _currentBid < _currentBinPrice);
                binBtn.textContent = `⚡ Hemen Al — ₺${Number(_currentBinPrice ?? 0).toLocaleString('tr-TR')}`;
                binBtn.style.display = binVisible ? '' : 'none';
            }
        }
    }

    function _showSoldBanner(buyer, price, itemName) {
        const banner = document.getElementById('auctionSoldBanner');
        if (!banner) return;
        const detail = document.getElementById('soldBannerDetail');
        if (detail) {
            const item = itemName ? `${itemName} — ` : '';
            detail.textContent = `${item}${price} — @${buyer} tarafından Hemen Alındı`;
        }
        banner.style.display = 'flex';
    }

    function _hideSoldBanner() {
        const banner = document.getElementById('auctionSoldBanner');
        if (banner) banner.style.display = 'none';
    }

    let _auctionMsgTimer = null;
    function setAuctionMsg(msg, type = '') {
        const el = document.getElementById('auctionMsg');
        el.textContent = msg;
        el.className = type;
        clearTimeout(_auctionMsgTimer);
        if (msg) {
            _auctionMsgTimer = setTimeout(() => {
                el.textContent = '';
                el.className = '';
            }, 6000);
        }
    }

    let _isHostPage = false;

    // ── Canlı yayın kalp throttle ────────────────────────────────────
    let _heartThrottleTimer   = null;
    let _heartThrottlePending = false;

    function _onStreamHeart() {
        _spawnFloatingHeart(true);
        if (_heartThrottleTimer) {
            _heartThrottlePending = true;
        } else {
            _fireLikeRequest();
            _heartThrottleTimer = setTimeout(() => {
                _heartThrottleTimer = null;
                if (_heartThrottlePending) {
                    _heartThrottlePending = false;
                    _fireLikeRequest();
                }
            }, 1500);
        }
    }

    function _fireLikeRequest() {
        if (!streamId || !Auth.getToken()) return;
        apiFetch(`/streams/${streamId}/like`, { method: 'POST' }).catch(() => {});
    }

    function _spawnFloatingHeart(isLocal) {
        const container = document.getElementById('videoContainer');
        if (!container) return;
        const heart = document.createElement('div');
        heart.className = 'floating-heart';
        const driftX = (Math.random() * 50 - 25) | 0;
        heart.style.setProperty('--hx', `${driftX}px`);
        heart.textContent = isLocal ? '❤️' : '🩷';
        container.appendChild(heart);
        heart.addEventListener('animationend', () => heart.remove(), { once: true });
        setTimeout(() => { if (heart.parentNode) heart.remove(); }, 2200);
    }
    let _isCoHost   = false;

    function _promoteToCoHost(promotedBy) {
        _isCoHost = true;

        // Moderatör rozeti göster
        const modBadge = document.getElementById('modBadge');
        if (modBadge) modBadge.style.display = '';

        // Auction UI'ını mevcut durumla yeniden senkronize et.
        // hostSetup'ı körce 'flex' yapmak yerine updateAuctionUI çağırıyoruz;
        // böylece açık artırma aktifse Start butonları gizli kalır.
        updateAuctionUI({
            status:          _currentAuctionStatus,
            current_bid:     _currentBid,
            current_bidder:  _currentBidder,
            item_name:       _currentItemName,
            listing_id:      _currentListingId,
            buy_it_now_price: _currentBinPrice,
            bid_count:       _lastBidCount,
        });

        // Viewer bileşenlerini gizle (co-host teklif vermez, yönetir)
        const viewerControls   = document.getElementById('viewerControls');
        const auctionListingBtn = document.getElementById('auctionListingBtn');
        if (viewerControls)    viewerControls.style.display    = 'none';
        if (auctionListingBtn) auctionListingBtn.style.display = 'none';

        // Co-host'a şık bir bildirim göster
        setAuctionMsg(`⭐ Tebrikler! @${promotedBy} sizi moderatör yaptı.`, 'success');

        // Chat ve teklif listesinde kullanıcı adlarına tıklama yetkisi (event delegation)
        document.getElementById('chatMessages')?.addEventListener('click', (e) => {
            const span = e.target.closest('[data-username]');
            if (span && span.dataset.username) _showModModal(span.dataset.username);
        });
        document.getElementById('bidsList')?.addEventListener('click', (e) => {
            const span = e.target.closest('[data-username]');
            if (span && span.dataset.username) _showModModal(span.dataset.username);
        });

        // Sonraki chat mesajlarında kullanıcı adı tıklamasını etkinleştir
        Chat.setUsernameTap(_showModModal);

        // Host ilanlarını yükle (moderatör ilan ekleyebilmeli)
        if (typeof loadHostListings === 'function') loadHostListings();
    }

    function _demoteFromCoHost() {
        _isCoHost = false;

        // Moderatör rozeti gizle
        const modBadge = document.getElementById('modBadge');
        if (modBadge) modBadge.style.display = 'none';

        // Host panellerini gizle
        const hostSetup    = document.getElementById('hostSetup');
        const hostControls = document.getElementById('hostControls');
        if (hostSetup)    hostSetup.style.display    = 'none';
        if (hostControls) hostControls.style.display = 'none';

        // Viewer bileşenlerini geri getir
        const viewerControls    = document.getElementById('viewerControls');
        const auctionListingBtn = document.getElementById('auctionListingBtn');
        if (viewerControls)    viewerControls.style.display    = 'flex';
        if (auctionListingBtn) auctionListingBtn.style.display = '';

        // Chat tıklama yetkisini kaldır
        Chat.setUsernameTap(null);

        setAuctionMsg('Moderatörlüğünüz kaldırıldı.', 'info');
    }

    function initAuction(sid, isHost) {
        _isHostPage = isHost;
        document.getElementById('auctionPanel').classList.add('visible');

        if (!isHost) {
            // Host panelleri gizle ama DOM'da bırak — Co-Host ataması sonrası gösterilebilir
            const _hs = document.getElementById('hostSetup');
            const _hc = document.getElementById('hostControls');
            if (_hs) _hs.style.display = 'none';
            if (_hc) _hc.style.display = 'none';
            // Host listing mode toggle — Co-Host atanırsa bağlanacak
            document.getElementById('btnListingMode')?.addEventListener('click', toggleListingMode);
            // Picker dışına tıklayınca kapat (host ile aynı listener)
            document.addEventListener('click', (e) => {
                const picker = document.getElementById('listingPicker');
                if (picker && !picker.contains(e.target) && e.target.id !== 'btnListingMode') {
                    picker.style.display = 'none';
                }
            });
            // Viewer: listing butonu tıklaması
            const lb = document.getElementById('auctionListingBtn');
            if (lb) lb.addEventListener('click', showListingModal);
        } else {
            document.getElementById('viewerControls').remove();
            document.getElementById('auctionListingBtn')?.remove();
            // Host: ilanları yükle
            loadHostListings();
            // Host: listing mode toggle
            document.getElementById('btnListingMode')?.addEventListener('click', toggleListingMode);
            // Picker dışına tıklayınca kapat
            document.addEventListener('click', (e) => {
                const picker = document.getElementById('listingPicker');
                if (picker && !picker.contains(e.target)) _closeListingPicker();
            });
        }

        updateAuctionUI({ status: 'idle', bid_count: 0 });
        Auction.connect(sid, isHost, (state) => updateAuctionUI(state));
    }

    // ── Host: ilan listesi yükleme (custom picker) ───────────────
    let _hostListings = [];

    async function loadHostListings() {
        try {
            // Gerçek host → kendi ilanları. Moderatör → host'un ilanları.
            const info = Stream.load();
            const hostId = info?.host_livekit_identity; // = str(host.id), viewer'da dolu
            let data;
            if (!_isHostPage && hostId) {
                // Moderatör: host'un ilanlarını yükle
                data = await apiFetch(`/listings?user_id=${hostId}`);
            } else {
                // Gerçek host: kendi ilanları
                data = await apiFetch('/listings/my?active=true');
            }
            _hostListings = Array.isArray(data) ? data : [];
            _buildPickerItems();
        } catch (err) {
            console.error('[loadHostListings] İlan yüklenemedi:', err);
        }
    }

    function _buildPickerItems() {
        const dd = document.getElementById('listingPickerDropdown');
        if (!dd) return;
        dd.innerHTML = '';
        if (!_hostListings.length) {
            dd.innerHTML = '<div style="padding:12px;text-align:center;color:#64748b;font-size:0.8rem;">Aktif ilanınız yok</div>';
            return;
        }
        _hostListings.forEach(l => {
            let imgs = l.image_urls || [];
            if (typeof imgs === 'string') { try { imgs = JSON.parse(imgs); } catch (_) { imgs = []; } }
            const rawImg = imgs.length ? imgs[0] : (l.image_url || null);
            const imgSrc = rawImg ? (rawImg.startsWith('http') || rawImg.startsWith('/') ? rawImg : `/uploads/${rawImg}`) : null;
            const priceStr = l.price ? '₺' + Number(l.price).toLocaleString('tr-TR') : '';
            const imgHtml = imgSrc
                ? `<img src="${imgSrc}" alt="" style="width:36px;height:36px;object-fit:cover;border-radius:6px;flex-shrink:0;pointer-events:none;" onerror="this.style.display='none'">`
                : `<div class="lp-img-placeholder" style="pointer-events:none;">📦</div>`;
            const infoHtml = `<div class="lp-info" style="pointer-events:none;"><div class="lp-title">${l.title}</div>${priceStr ? `<div class="lp-price">${priceStr}</div>` : ''}</div>`;
            const item = document.createElement('div');
            item.className = 'lp-item';
            item.dataset.id = String(l.id);
            item.innerHTML = imgHtml + infoHtml;
            dd.appendChild(item);
        });
        // Event delegation: tüm tıklamalar tek listenerdan
        dd.onclick = (e) => {
            const item = e.target.closest('.lp-item');
            if (!item) return;
            const id = parseInt(item.dataset.id, 10);
            const l = _hostListings.find(x => x.id === id);
            if (!l) return;
            let imgs = l.image_urls || [];
            if (typeof imgs === 'string') { try { imgs = JSON.parse(imgs); } catch (_) { imgs = []; } }
            const rawImg = imgs.length ? imgs[0] : (l.image_url || null);
            const imgSrc = rawImg ? (rawImg.startsWith('http') || rawImg.startsWith('/') ? rawImg : `/uploads/${rawImg}`) : null;
            _selectListing(id, l.title, imgSrc, l.price);
        };
    }

    function toggleListingPicker() {
        const dd = document.getElementById('listingPickerDropdown');
        const trigger = document.getElementById('listingPickerTrigger');
        if (!dd) return;
        const open = dd.classList.toggle('open');
        trigger.classList.toggle('open', open);
    }

    function _closeListingPicker() {
        document.getElementById('listingPickerDropdown')?.classList.remove('open');
        document.getElementById('listingPickerTrigger')?.classList.remove('open');
    }

    function _selectListing(id, title, imgSrc, price) {
        _selectedListingId = id;
        // Trigger güncelle
        const trigger = document.getElementById('listingPickerTrigger');
        const priceStr = price ? ' — ₺' + Number(price).toLocaleString('tr-TR') : '';
        trigger.innerHTML = imgSrc
            ? `<img src="${imgSrc}" alt="">`
            : `<div style="width:26px;height:26px;background:#334155;border-radius:4px;flex-shrink:0;"></div>`;
        trigger.innerHTML += `<span>${title}${priceStr}</span><span style="color:#64748b;font-size:10px;">▾</span>`;
        trigger.onclick = toggleListingPicker;
        // Seçili item'ı işaretle
        document.querySelectorAll('.lp-item').forEach(el => el.classList.toggle('selected', parseInt(el.dataset.id) === id));
        _closeListingPicker();
    }

    function toggleListingMode() {
        _listingMode = !_listingMode;
        const btn = document.getElementById('btnListingMode');
        const picker = document.getElementById('listingPicker');
        const itemInput = document.getElementById('auctionItemInput');
        btn.classList.toggle('active', _listingMode);
        picker.style.display = _listingMode ? '' : 'none';
        itemInput.style.display = _listingMode ? 'none' : '';
        if (!_listingMode) {
            _selectedListingId = null;
            // Picker'ı sıfırla
            const trigger = document.getElementById('listingPickerTrigger');
            if (trigger) { trigger.innerHTML = '<span id="listingPickerText">— İlan seçin —</span><span style="color:#64748b;font-size:10px;">▾</span>'; trigger.onclick = toggleListingPicker; }
            document.querySelectorAll('.lp-item').forEach(el => el.classList.remove('selected'));
            _closeListingPicker();
        }
    }

    function _resetListingMode() {
        _listingMode = false;
        _selectedListingId = null;
        const btn = document.getElementById('btnListingMode');
        const picker = document.getElementById('listingPicker');
        const itemInput = document.getElementById('auctionItemInput');
        const binInput = document.getElementById('auctionBinPrice');
        if (btn) btn.classList.remove('active');
        if (picker) picker.style.display = 'none';
        if (itemInput) itemInput.style.display = '';
        if (binInput) binInput.value = '';
        const trigger = document.getElementById('listingPickerTrigger');
        if (trigger) { trigger.innerHTML = '<span id="listingPickerText">— İlan seçin —</span><span style="color:#64748b;font-size:10px;">▾</span>'; trigger.onclick = toggleListingPicker; }
        document.querySelectorAll('.lp-item').forEach(el => el.classList.remove('selected'));
        _closeListingPicker();
    }

    // HOST: Hızlı Başlat — dialog olmadan Ürün N / ₺1 ile anında başlat
    document.getElementById('btnAuctionQuickStart')?.addEventListener('click', async () => {
        _quickAuctionCount++;
        try {
            await Auction.startAuction(`Ürün ${_quickAuctionCount}`, 1, null, null);
            setAuctionMsg(`⚡ Ürün ${_quickAuctionCount} başlatıldı!`, 'success');
        } catch (e) {
            _quickAuctionCount--;
            console.error('[Auction] Hızlı başlatma hatası:', e);
            if (window.Sentry) Sentry.captureException(e);
            setAuctionMsg(e.detail || e.message || 'Hata', 'error');
        }
    });

    // HOST: Başlat
    document.getElementById('btnAuctionStart')?.addEventListener('click', async () => {
        const startPrice = _parsePrice('auctionStartPrice');
        if (isNaN(startPrice) || startPrice < 0) return setAuctionMsg('Geçerli başlangıç fiyatı girin', 'error');
        const binRaw = _parsePrice('auctionBinPrice');
        const binPrice = !isNaN(binRaw) && binRaw > 0 ? binRaw : null;
        if (_listingMode) {
            // DOM'daki seçili item'dan fallback oku
            if (!_selectedListingId) {
                const sel = document.querySelector('#listingPickerDropdown .lp-item.selected');
                if (sel) _selectedListingId = parseInt(sel.dataset.id, 10);
            }
            if (!_selectedListingId) return setAuctionMsg('Bir ilan seçin', 'error');
            try {
                await Auction.startAuction(null, startPrice, _selectedListingId, binPrice);
                setAuctionMsg('Açık artırma başladı!', 'success');
            } catch (e) { setAuctionMsg(e.detail || e.message || 'Hata', 'error'); }
            return;
        }
        const itemName = document.getElementById('auctionItemInput').value.trim();
        if (!itemName) return setAuctionMsg('Ürün adı girin', 'error');
        try {
            await Auction.startAuction(itemName, startPrice, null, binPrice);
            setAuctionMsg('Açık artırma başladı!', 'success');
        } catch (e) { setAuctionMsg(e.detail || e.message || 'Hata', 'error'); }
    });

    // ── Viewer: ilan popup ───────────────────────────────────────
    let _lmImgs = [], _lmIdx = 0;

    function lmSlide(dir) {
        if (_lmImgs.length < 2) return;
        _lmIdx = (_lmIdx + dir + _lmImgs.length) % _lmImgs.length;
        document.getElementById('listingModalTrack').style.transform = `translateX(-${_lmIdx * 100}%)`;
        document.querySelectorAll('.lm-dot').forEach((d, i) => d.classList.toggle('active', i === _lmIdx));
        document.getElementById('lmArrowL').style.display = _lmIdx === 0 ? 'none' : 'flex';
        document.getElementById('lmArrowR').style.display = _lmIdx === _lmImgs.length - 1 ? 'none' : 'flex';
    }

    async function showListingModal(e) {
        if (e) e.preventDefault();
        if (!_currentListingId) return;
        try {
            const listing = await apiFetch(`/listings/${_currentListingId}`);
            let raw = listing.image_urls || [];
            if (typeof raw === 'string') { try { raw = JSON.parse(raw); } catch (_) { raw = []; } }
            if (!raw.length && listing.image_url) raw = [listing.image_url];
            _lmImgs = raw.map(r => r.startsWith('http') || r.startsWith('/') ? r : `/uploads/${r}`);
            _lmIdx = 0;

            const slider = document.getElementById('listingModalSlider');
            const track = document.getElementById('listingModalTrack');
            const dots = document.getElementById('lmDots');
            if (_lmImgs.length) {
                track.innerHTML = _lmImgs.map(src => `<img src="${src}" alt="">`).join('');
                track.style.transform = 'translateX(0)';
                dots.innerHTML = _lmImgs.length > 1
                    ? _lmImgs.map((_, i) => `<div class="lm-dot${i === 0 ? ' active' : ''}"></div>`).join('')
                    : '';
                document.getElementById('lmArrowL').style.display = 'none';
                document.getElementById('lmArrowR').style.display = _lmImgs.length > 1 ? 'flex' : 'none';
                let tx = 0;
                track.ontouchstart = ev => { tx = ev.touches[0].clientX; };
                track.ontouchend = ev => { const dx = ev.changedTouches[0].clientX - tx; if (Math.abs(dx) > 40) lmSlide(dx < 0 ? 1 : -1); };
                slider.style.display = 'block';
            } else {
                slider.style.display = 'none';
            }
            document.getElementById('listingModalTitle').textContent = listing.title || '';
            document.getElementById('listingModalPrice').textContent = listing.price != null
                ? '₺ ' + Number(listing.price).toLocaleString('tr-TR')
                : 'Fiyat Belirtilmemiş';
            document.getElementById('listingModalSeller').textContent = listing.user?.username ? `@${listing.user.username}` : '';
            const descEl = document.getElementById('listingModalDesc');
            if (listing.description) { descEl.textContent = listing.description; descEl.style.display = 'block'; }
            else descEl.style.display = 'none';
            document.getElementById('listingModalOverlay').style.display = 'flex';
        } catch (_) { }
    }

    function closeListingModal(e) {
        if (e.target === document.getElementById('listingModalOverlay')) {
            document.getElementById('listingModalOverlay').style.display = 'none';
        }
    }

    // HOST: Duraklat
    document.getElementById('btnAuctionPause')?.addEventListener('click', async () => {
        try { await Auction.pauseAuction(); setAuctionMsg('Duraklatıldı', ''); }
        catch (e) { setAuctionMsg(e.message, 'error'); }
    });

    // HOST: Devam
    document.getElementById('btnAuctionResume')?.addEventListener('click', async () => {
        try { await Auction.resumeAuction(); setAuctionMsg('Devam ediyor', 'success'); }
        catch (e) { setAuctionMsg(e.message, 'error'); }
    });

    // HOST: Teklifi Kabul Et — styled modal
    document.getElementById('btnAuctionAccept')?.addEventListener('click', () => {
        const modal = document.getElementById('acceptModal');
        document.getElementById('acceptModalItem').textContent = _currentItemName || '—';
        document.getElementById('acceptModalPrice').textContent = _currentBid
            ? '₺' + Number(_currentBid).toLocaleString('tr-TR')
            : '—';
        document.getElementById('acceptModalBidder').textContent = _currentBidder
            ? '@' + _currentBidder : '—';
        modal.style.display = 'flex';
    });

    document.getElementById('acceptModalCancel')?.addEventListener('click', () => {
        document.getElementById('acceptModal').style.display = 'none';
    });

    document.getElementById('acceptModalConfirm')?.addEventListener('click', async () => {
        document.getElementById('acceptModal').style.display = 'none';
        try {
            await Auction.acceptBid();
            setAuctionMsg('Teklif kabul edildi! Özet sohbete gönderildi.', 'success');
            setTimeout(() => setAuctionMsg('', ''), 5000);
        } catch (e) { setAuctionMsg(e.message, 'error'); }
    });

    // Modal dışına tıklayınca kapat
    document.getElementById('acceptModal')?.addEventListener('click', (e) => {
        if (e.target === document.getElementById('acceptModal'))
            document.getElementById('acceptModal').style.display = 'none';
    });

    // ── VIEWER: Hemen Al ──────────────────────────────────────────────

    function _showBuyItNowRequestModal(buyerUsername, price, itemName) {
        document.getElementById('binReqModalItem').textContent = itemName || '—';
        document.getElementById('binReqModalPrice').textContent = price != null
            ? '₺' + Number(price).toLocaleString('tr-TR')
            : '—';
        document.getElementById('binReqModalBuyer').textContent = '@' + buyerUsername;
        document.getElementById('binRequestModal').style.display = 'flex';
    }

    function _closeBuyItNowRequestModal() {
        document.getElementById('binRequestModal').style.display = 'none';
    }

    document.getElementById('binReqModalReject')?.addEventListener('click', async () => {
        _closeBuyItNowRequestModal();
        try {
            await Auction.rejectBuyItNow();
            setAuctionMsg('Hemen Al talebi reddedildi.', '');
        } catch (e) {
            console.error('[Auction] Hemen Al red hatası:', e);
            if (window.Sentry) Sentry.captureException(e);
            setAuctionMsg(e.detail || e.message || 'Hata oluştu', 'error');
        }
    });

    document.getElementById('binReqModalAccept')?.addEventListener('click', async () => {
        const btn = document.getElementById('binReqModalAccept');
        btn.disabled = true;
        btn.textContent = 'İşleniyor...';
        try {
            await Auction.acceptBuyItNow();
            _closeBuyItNowRequestModal();
        } catch (e) {
            console.error('[Auction] Hemen Al kabul hatası:', e);
            if (window.Sentry) Sentry.captureException(e);
            _closeBuyItNowRequestModal();
            setAuctionMsg(e.detail || e.message || 'Hata oluştu', 'error');
        } finally {
            if (btn) { btn.disabled = false; btn.textContent = 'Onayla'; }
        }
    });

    document.getElementById('binRequestModal')?.addEventListener('click', (e) => {
        if (e.target === document.getElementById('binRequestModal')) _closeBuyItNowRequestModal();
    });

    let _binModalWaiting = false;
    let _iAmBinBuyer = false; // Bu viewer BIN talebini başlattıysa true

    function _openBuyItNowModal() {
        _binModalWaiting = false;
        document.getElementById('binModalItem').textContent = _currentItemName || '—';
        document.getElementById('binModalPrice').textContent = _currentBinPrice != null
            ? '₺' + Number(_currentBinPrice).toLocaleString('tr-TR')
            : '—';
        document.getElementById('binModalDesc').style.display = '';
        document.getElementById('binModalWaiting').style.display = 'none';
        document.getElementById('binModalActions').style.display = 'flex';
        // Önceki işlemden kalabilecek disabled/loading durumunu sıfırla
        const confirmBtn = document.getElementById('binModalConfirm');
        if (confirmBtn) { confirmBtn.disabled = false; confirmBtn.textContent = 'Satın Al'; }
        document.getElementById('buyItNowModal').style.display = 'flex';
    }

    function _closeBuyItNowModal() {
        _binModalWaiting = false;
        _iAmBinBuyer = false;
        document.getElementById('buyItNowModal').style.display = 'none';
    }

    document.getElementById('btnBuyItNow')?.addEventListener('click', _openBuyItNowModal);

    document.getElementById('binModalCancel')?.addEventListener('click', _closeBuyItNowModal);

    document.getElementById('buyItNowModal')?.addEventListener('click', (e) => {
        // Onay beklenirken backdrop tıklamasıyla kapanmayı engelle
        if (_binModalWaiting) return;
        if (e.target === document.getElementById('buyItNowModal')) _closeBuyItNowModal();
    });

    document.getElementById('binModalConfirm')?.addEventListener('click', async () => {
        const confirmBtn = document.getElementById('binModalConfirm');
        confirmBtn.disabled = true;
        confirmBtn.textContent = 'İşleniyor...';
        try {
            await Auction.buyItNow();
            // Modal kapanmıyor — host onayı bekleniyor durumuna geç
            _iAmBinBuyer = true;
            _binModalWaiting = true;
            document.getElementById('binModalDesc').style.display = 'none';
            document.getElementById('binModalActions').style.display = 'none';
            document.getElementById('binModalWaiting').style.display = '';
        } catch (e) {
            console.error('[Auction] Hemen Al başarısız:', e);
            if (window.Sentry) Sentry.captureException(e);
            _closeBuyItNowModal();
            setAuctionMsg(e.detail || e.message || 'Hemen Al sırasında hata oluştu', 'error');
        } finally {
            if (!_binModalWaiting && confirmBtn) {
                confirmBtn.disabled = false;
                confirmBtn.textContent = 'Satın Al';
            }
        }
    });

    // HOST: Bitir
    document.getElementById('btnAuctionEnd')?.addEventListener('click', async () => {
        if (!confirm('Açık artırmayı bitirmek istediğinizden emin misiniz?')) return;
        try { await Auction.endAuction(); setAuctionMsg('Açık artırma tamamlandı', ''); }
        catch (e) { setAuctionMsg(e.message, 'error'); }
    });

    // VIEWER: Preset teklif
    async function quickBid(increment) {
        if (_currentAuctionStatus !== 'active') return setAuctionMsg('Açık artırma aktif değil', 'error');
        const amount = _currentBid + increment;
        await submitBid(amount);
    }

    // VIEWER: Custom teklif
    document.getElementById('btnCustomBid')?.addEventListener('click', async () => {
        const val = _parsePrice('customBidInput');
        if (isNaN(val) || val <= 0) return setAuctionMsg('Geçerli tutar girin', 'error');
        await submitBid(val);
    });

    async function submitBid(amount) {
        try {
            const state = await Auction.placeBid(amount);
            if (state) updateAuctionUI(state);
            setAuctionMsg(`₺${Number(amount).toLocaleString('tr-TR')} teklifiniz alındı!`, 'success');
            document.getElementById('customBidInput') && (document.getElementById('customBidInput').value = '');
        } catch (e) { setAuctionMsg(e.message, 'error'); }
    }

    // ── Moderasyon ───────────────────────────────────────────────────

    const _mutedUsers = new Set(); // host/cohost tarafında takip edilen mute listesi
    const _modUsers   = new Set(); // aktif moderatörler (mod_promoted/demoted eventlerinden)
    let _modTargetUsername = null;

    function _showModModal(username) {
        _modTargetUsername = username;
        document.getElementById('modModalTarget').textContent = `@${username}`;
        const isMuted = _mutedUsers.has(username);
        const isMod   = _modUsers.has(username);
        document.getElementById('modBtnMute').style.display    = isMuted ? 'none' : 'block';
        document.getElementById('modBtnUnmute').style.display  = isMuted ? 'block' : 'none';
        // Promote / Demote: sadece gerçek host görebilir, duruma göre biri görünür
        document.getElementById('modBtnPromote').style.display = (_isHostPage && !isMod) ? 'block' : 'none';
        document.getElementById('modBtnDemote').style.display  = (_isHostPage && isMod)  ? 'block' : 'none';
        // Sahneye Davet Et / Sahneden Al: sadece gerçek host, duruma göre
        const cohostBtn = document.getElementById('modBtnCoHost');
        if (_isHostPage) {
            if (!_coHostUsername) {
                // Sahnede kimse yok → davet et
                cohostBtn.textContent = '🎬 Sahneye Davet Et';
                cohostBtn.style.background = '#6366f1';
                cohostBtn.dataset.cohostAction = 'invite';
                cohostBtn.style.display = 'block';
            } else if (_coHostUsername === username) {
                // Bu kişi sahnede → sahneden al
                cohostBtn.textContent = '📵 Sahneden Al';
                cohostBtn.style.background = '#ef4444';
                cohostBtn.dataset.cohostAction = 'remove';
                cohostBtn.style.display = 'block';
            } else {
                // Başkası sahnede → bu kişiyi davet edemez
                cohostBtn.style.display = 'none';
            }
        } else {
            cohostBtn.style.display = 'none';
        }
        document.getElementById('modMsg').textContent = '';
        // Her açılışta butonları aktif et
        document.querySelectorAll('.mod-btn').forEach(b => b.disabled = false);
        document.getElementById('modModal').style.display = 'flex';
    }

    function _closeModModal() {
        document.getElementById('modModal').style.display = 'none';
        _modTargetUsername = null;
    }

    function _setModMsg(text, color = '#94a3b8') {
        const el = document.getElementById('modMsg');
        el.textContent = text;
        el.style.color = color;
    }

    async function _modAction(action) {
        if (!_modTargetUsername || !streamId) return;
        const btns = document.querySelectorAll('.mod-btn');
        btns.forEach(b => b.disabled = true);
        try {
            await apiFetch(`/moderation/${streamId}/${action}`, {
                method: 'POST',
                body: JSON.stringify({ username: _modTargetUsername }),
            });
            if (action === 'mute') {
                _mutedUsers.add(_modTargetUsername);
                _setModMsg('Kullanıcı susturuldu.', '#fbbf24');
                setTimeout(_closeModModal, 1200);
            } else if (action === 'unmute') {
                _mutedUsers.delete(_modTargetUsername);
                _setModMsg('Susturma kaldırıldı.', '#4ade80');
                setTimeout(_closeModModal, 1200);
            } else if (action === 'kick') {
                _setModMsg('Kullanıcı yayından atıldı.', '#f87171');
                setTimeout(_closeModModal, 1200);
            } else if (action === 'promote') {
                _modUsers.add(_modTargetUsername);
                _setModMsg('Kullanıcı moderatör yapıldı!', '#fbbf24');
                setTimeout(_closeModModal, 1200);
            } else if (action === 'demote') {
                _modUsers.delete(_modTargetUsername);
                _setModMsg('Moderatörlük geri alındı.', '#94a3b8');
                setTimeout(_closeModModal, 1200);
            }
        } catch (e) {
            _setModMsg(e.detail || e.message || 'Hata oluştu', '#f87171');
            btns.forEach(b => b.disabled = false);
        }
    }

    document.getElementById('modBtnMute')?.addEventListener('click',    () => _modAction('mute'));
    document.getElementById('modBtnUnmute')?.addEventListener('click',  () => _modAction('unmute'));
    document.getElementById('modBtnKick')?.addEventListener('click',    () => _modAction('kick'));
    document.getElementById('modBtnPromote')?.addEventListener('click', () => _modAction('promote'));
    document.getElementById('modBtnDemote')?.addEventListener('click',  () => _modAction('demote'));
    document.getElementById('modBtnCoHost')?.addEventListener('click',  async () => {
        const target = _modTargetUsername;
        const action = document.getElementById('modBtnCoHost').dataset.cohostAction;
        _closeModModal();
        if (!target || !streamId) return;
        try {
            if (action === 'remove') {
                _coHostUsername = null;
                document.getElementById('videoContainer')?.querySelector('.cohost-pip')?.remove();
                await Stream.removeCoHost(streamId, target);
            } else {
                await Stream.inviteCoHost(streamId, target);
                const msg = document.createElement('div');
                msg.style.cssText = 'position:fixed;top:24px;left:50%;transform:translateX(-50%);z-index:9999;background:#6366f1;color:#fff;padding:10px 20px;border-radius:10px;font-size:0.88rem;font-weight:600;box-shadow:0 4px 16px rgba(0,0,0,0.4);';
                msg.textContent = `🎬 @${target} sahneye davet edildi`;
                document.body.appendChild(msg);
                setTimeout(() => msg.remove(), 3000);
            }
        } catch (e) {
            console.error('[COHOST] Modal aksiyonu başarısız:', e);
        }
    });
    document.getElementById('modBtnCancel')?.addEventListener('click', _closeModModal);
    document.getElementById('modModal')?.addEventListener('click', (e) => {
        if (e.target === document.getElementById('modModal')) _closeModModal();
    });

    // ── Co-Host: host tarafı ────────────────────────────────────────

    let _coHostUsername = null; // cohost_accepted WS eventinden gelir

    function _addHostRemoveBtn(pipEl) {
        // Önceki butonu temizle
        pipEl.querySelector('.pip-remove-btn')?.remove();
        const btn = document.createElement('button');
        btn.className = 'pip-remove-btn';
        btn.title = 'Sahneden Kaldır';
        btn.textContent = '✕ Sahneden Al';
        btn.onclick = async () => {
            if (!_coHostUsername || !streamId) return;
            const target = _coHostUsername;
            _coHostUsername = null;
            pipEl.remove(); // anında kaldır, TrackUnsubscribed'ı bekleme
            try {
                await Stream.removeCoHost(streamId, target);
            } catch (e) {
                console.error('[COHOST] removeCoHost hatası:', e);
            }
        };
        pipEl.appendChild(btn);
    }

    // ── Co-Host: davet modalı (viewer) ──────────────────────────────

    let _isSelfCoHost = false;

    function _showCoHostInviteModal(hostUsername) {
        document.getElementById('cohostInviteText').textContent =
            `@${hostUsername} seni sahneye davet ediyor! Kameran ve mikrofonun açılacak. Kabul ediyor musun?`;
        document.getElementById('cohostInviteModal').style.display = 'flex';
    }

    document.getElementById('cohostInviteReject')?.addEventListener('click', () => {
        document.getElementById('cohostInviteModal').style.display = 'none';
    });

    document.getElementById('cohostInviteAccept')?.addEventListener('click', async () => {
        document.getElementById('cohostInviteModal').style.display = 'none';
        _isSelfCoHost = true; // disconnectRoom() tetiklenmeden önce set et
        try {
            await Stream.acceptCoHostInvite(streamId);
            // PiP'e "Sahneden Çık" butonu ekle
            const pipEl = document.getElementById('videoContainer')?.querySelector('.cohost-pip');
            if (pipEl) {
                const btn = document.createElement('button');
                btn.className = 'pip-remove-btn';
                btn.textContent = '✕ Sahneden Çık';
                btn.onclick = _handleCoHostRemoved;
                pipEl.appendChild(btn);
            }
        } catch (e) {
            _isSelfCoHost = false; // bağlantı başarısız — flag'i geri al
            console.error('[COHOST] Sahneye bağlanılamadı:', e);
            const el = document.createElement('div');
            el.style.cssText = 'position:fixed;top:24px;left:50%;transform:translateX(-50%);z-index:9999;background:#ef4444;color:#fff;padding:10px 20px;border-radius:10px;font-size:0.88rem;';
            el.textContent = 'Sahneye bağlanılamadı: ' + (e.message || 'Hata');
            document.body.appendChild(el);
            setTimeout(() => el.remove(), 4000);
        }
    });

    async function _handleCoHostRemoved() {
        if (!_isSelfCoHost) return;
        _isSelfCoHost = false;
        // PiP kutusunu kaldır
        const pipEl = document.getElementById('videoContainer')?.querySelector('.cohost-pip');
        if (pipEl) pipEl.remove();
        // Gönüllü ayrılmayı herkese bildir (host dahil modal sync olsun)
        if (streamId) {
            try { await Stream.leaveCoHost(streamId); } catch (_) {}
        }
        // Co-host odasından çık — kamera/mikrofon kapanır, TrackUnsubscribed tetiklenir
        await disconnectRoom();
        // Viewer olarak yeniden bağlan
        const info = Stream.load();
        if (info) {
            connectRoom({
                livekit_url: info.livekit_url,
                token: info.token,
                isHost: false,
                hostIdentity: info.host_livekit_identity || null,
                remoteVideoEl: document.getElementById('mainVideo'),
                remoteAudioEl: document.getElementById('remoteAudio'),
                onDisconnect: () => { if (!_isSelfCoHost) _onStreamEndedViewer(); },
                onRemoteVideo: () => {},
            });
        }
        const el = document.createElement('div');
        el.style.cssText = 'position:fixed;top:24px;left:50%;transform:translateX(-50%);z-index:9999;background:#475569;color:#fff;padding:10px 20px;border-radius:10px;font-size:0.88rem;';
        el.textContent = '📵 Sahneden kaldırıldınız';
        document.body.appendChild(el);
        setTimeout(() => el.remove(), 3000);
    }

    // ── Viewer: muted/kicked event handler ──────────────────────────

    let _selfMuted = false;

    function _onSelfMuted() {
        if (_selfMuted) return;
        _selfMuted = true;
        const input  = document.getElementById('chatInput');
        const sendBtn = document.getElementById('chatSendBtn');
        const bidMsg  = document.getElementById('auctionMsg');
        const viewerCtrl = document.getElementById('viewerControls');

        if (input) { input.disabled = true; input.placeholder = '🔇 Susturuldunuz'; }
        if (sendBtn) sendBtn.disabled = true;
        if (viewerCtrl) viewerCtrl.querySelectorAll('button, input').forEach(el => el.disabled = true);
        if (bidMsg) { bidMsg.textContent = 'Bu yayında susturuldunuz'; bidMsg.className = 'error'; }

        // Kalıcı banner göster
        if (!document.getElementById('mutedBanner')) {
            const banner = document.createElement('div');
            banner.id = 'mutedBanner';
            banner.style.cssText = 'background:#d97706;color:#fff;text-align:center;padding:7px 12px;font-size:0.78rem;font-weight:700;letter-spacing:0.3px;flex-shrink:0;';
            banner.textContent = '🔇 Bu yayında susturuldunuz — mesaj ve teklif gönderemezsiniz';
            const chatPanel = document.getElementById('chatPanel');
            if (chatPanel) chatPanel.prepend(banner);
        }
    }

    function _onSelfUnmuted() {
        _selfMuted = false;
        const input  = document.getElementById('chatInput');
        const sendBtn = document.getElementById('chatSendBtn');
        const bidMsg  = document.getElementById('auctionMsg');
        const viewerCtrl = document.getElementById('viewerControls');

        if (input) { input.disabled = false; input.placeholder = 'Mesaj yaz...'; }
        if (sendBtn) sendBtn.disabled = false;
        if (viewerCtrl) viewerCtrl.querySelectorAll('button, input').forEach(el => el.disabled = false);
        if (bidMsg) { bidMsg.textContent = ''; bidMsg.className = ''; }

        // Banneri kaldır
        document.getElementById('mutedBanner')?.remove();
    }

    function _onSelfKicked() {
        Chat.disconnect();
        try { Auction.disconnect(); } catch (_) {}
        try { disconnectRoom(); } catch (_) {}
        const el = document.createElement('div');
        el.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.92);z-index:9999;display:flex;align-items:center;justify-content:center;';
        el.innerHTML = `
            <div style="text-align:center;color:#fff;padding:2rem;">
                <div style="font-size:3rem;margin-bottom:1rem;">🚫</div>
                <div style="font-size:1.3rem;font-weight:700;margin-bottom:0.5rem;">Yayından Atıldınız</div>
                <div style="color:#94a3b8;margin-bottom:1.5rem;">Bu yayına erişiminiz kısıtlandı.</div>
                <div style="color:#64748b;font-size:0.85rem;">Ana sayfaya yönlendiriliyorsunuz...</div>
            </div>`;
        document.body.appendChild(el);
        setTimeout(() => { Stream.clear(); window.location.href = '/'; }, 3000);
    }

    // ── Sabitlenmiş mesaj ────────────────────────────────────────────

    function _showPinBanner(content) {
        const banner    = document.getElementById('pinBanner');
        const text      = document.getElementById('pinText');
        const closeBtn  = banner ? banner.querySelector('.pin-close') : null;
        if (!banner || !text) return;
        if (!content) {
            _hidePinBanner();
            return;
        }
        text.textContent = content;
        // Close butonu sadece host'a görünür
        if (closeBtn) closeBtn.style.display = _isHostPage ? '' : 'none';
        banner.classList.add('visible');
    }

    function _hidePinBanner() {
        const banner = document.getElementById('pinBanner');
        if (banner) banner.classList.remove('visible');
    }

    // ── Host pin girişi ──────────────────────────────────────────────
    function _togglePinInput() {
        const area = document.getElementById('pinInputArea');
        if (!area) return;
        const opening = !area.classList.contains('open');
        area.classList.toggle('open', opening);
        if (opening) {
            const ta = document.getElementById('pinTextarea');
            if (ta) ta.focus();
        } else {
            const ta = document.getElementById('pinTextarea');
            if (ta) ta.value = '';
            const cc = document.getElementById('pinCharCount');
            if (cc) cc.textContent = '0/120';
        }
    }

    function _sendHostPin() {
        const ta = document.getElementById('pinTextarea');
        if (!ta) return;
        const content = ta.value.trim();
        if (!content) return;
        Chat.sendPin(content);
        ta.value = '';
        const cc = document.getElementById('pinCharCount');
        if (cc) cc.textContent = '0/120';
        document.getElementById('pinInputArea')?.classList.remove('open');
    }

    function _clearHostPin() {
        Chat.sendPin('');
    }

    // ── Sohbet ──────────────────────────────────────────────────────

    function initChat(sid, isHost) {
        _isHostPage = isHost; // _showPinBanner global scope'ta erişir
        const panel = document.getElementById('chatPanel');
        panel.style.display = '';

        if (Auth.getToken()) {
            document.getElementById('chatInputRow').style.display = 'flex';
        }

        const _viewerCountEl = document.getElementById('viewerCountText');
        const _onViewerCount = (n) => { if (_viewerCountEl) _viewerCountEl.textContent = `👁 ${n}`; };

        if (isHost) {
            Chat.connect(sid, {
                onViewerCount: _onViewerCount,
                onUsernameTap: _showModModal,
                // Host: mod_promoted/demoted → _modUsers senkronize et
                onModPromoted: (msg) => { if (msg.username) _modUsers.add(msg.username); },
                onModDemoted:  (msg) => { if (msg.username) _modUsers.delete(msg.username); },
                onHostPin: _showPinBanner,
                onStreamLike: () => _spawnFloatingHeart(false),
                onCoHostAccepted: (username) => {
                    _coHostUsername = username;
                    // PiP zaten oluşmuşsa butonu ekle; yoksa onCoHostPip callback'i ekler
                    const pipEl = document.getElementById('videoContainer')?.querySelector('.cohost-pip');
                    if (pipEl) _addHostRemoveBtn(pipEl);
                },
                onCoHostRemoved: () => {
                    // Başka bir client tarafından kaldırıldı — PiP'i temizle
                    _coHostUsername = null;
                    document.getElementById('videoContainer')?.querySelector('.cohost-pip')?.remove();
                },
                myUserId: Auth.getUser()?.id ?? null,
            });

            // Host: sabitleme butonunu göster + karakter sayacı
            const _pinRow = document.getElementById('hostPinRow');
            if (_pinRow) _pinRow.classList.add('visible');
            const _pinTa = document.getElementById('pinTextarea');
            const _pinCc = document.getElementById('pinCharCount');
            if (_pinTa && _pinCc) {
                _pinTa.addEventListener('input', () => {
                    _pinCc.textContent = `${_pinTa.value.length}/120`;
                });
                _pinTa.addEventListener('keydown', (e) => {
                    // Ctrl/Cmd+Enter → gönder
                    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
                        e.preventDefault();
                        _sendHostPin();
                    }
                });
            }

            // Host: teklif listesinde kullanıcı adına tıklayınca mod modal aç
            document.getElementById('bidsList').addEventListener('click', (e) => {
                const span = e.target.closest('[data-username]');
                if (span && span.dataset.username) _showModModal(span.dataset.username);
            });
        } else {
            const _currentUsername = Auth.getUser()?.username || null;
            Chat.connect(sid, {
                onStreamEnded: _onStreamEndedViewer,
                onViewerCount: _onViewerCount,
                onMuted:   _onSelfMuted,
                onUnmuted: _onSelfUnmuted,
                onKicked:  _onSelfKicked,
                onModPromoted: (msg) => {
                    if (msg.username) _modUsers.add(msg.username);
                    if (_currentUsername && msg.username === _currentUsername) {
                        _promoteToCoHost(msg.promoted_by || '?');
                    }
                },
                onModDemoted: (msg) => {
                    if (msg.username) _modUsers.delete(msg.username);
                    if (_currentUsername && msg.username === _currentUsername) {
                        _demoteFromCoHost();
                    }
                },
                onHostPin: _showPinBanner,
                onStreamLike: () => _spawnFloatingHeart(false),
                onCoHostInvite: (hostUsername, targetUsername) => {
                    if (_currentUsername && targetUsername === _currentUsername && !_isSelfCoHost) {
                        _showCoHostInviteModal(hostUsername);
                    }
                },
                onCoHostRemoved: (targetUsername) => {
                    if (_currentUsername && targetUsername === _currentUsername) {
                        _handleCoHostRemoved();
                    } else if (!_isSelfCoHost) {
                        // Başka birisi sahneden kaldırıldı — PiP'i temizle
                        document.getElementById('videoContainer')?.querySelector('.cohost-pip')?.remove();
                    }
                },
                myUserId: Auth.getUser()?.id ?? null,
            });
        }

        // İlk mesaj gelince "empty" yazısını kaldır
        const messages = document.getElementById('chatMessages');
        const observer = new MutationObserver(() => {
            const empty = document.getElementById('chatEmpty');
            if (empty && messages.children.length > 1) empty.remove();
        });
        observer.observe(messages, { childList: true });

        const input = document.getElementById('chatInput');
        const sendBtn = document.getElementById('chatSendBtn');

        function doSend() {
            if (_selfMuted) return;
            const content = input.value.trim();
            if (!content) return;
            Chat.sendMessage(content);
            input.value = '';
        }

        sendBtn.addEventListener('click', doSend);
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') doSend();
        });
    }

    // ── Fiyat Alanı Formatlama ───────────────────────────────────────
    function _attachPriceFormat(id) {
        const el = document.getElementById(id);
        if (!el) return;
        el.addEventListener('input', () => {
            const digits = el.value.replace(/[^\d]/g, '');
            el.value = digits.replace(/(\d)(?=(\d{3})+$)/g, '$1.');
        });
    }
    _attachPriceFormat('auctionStartPrice');
    _attachPriceFormat('auctionBinPrice');
    _attachPriceFormat('customBidInput');

    function _parsePrice(id) {
        const el = document.getElementById(id);
        if (!el) return NaN;
        return parseFloat(el.value.replace(/\./g, '')) || NaN;
    }

    init();
    </script>
