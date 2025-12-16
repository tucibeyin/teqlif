document.addEventListener('DOMContentLoaded', () => {
    // 1. AYARLAR
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    window.CURRENT_SOCKET = null;
    let AUCTION_ACTIVE = CONFIG.auctionActive;
    let activeGiftTarget = null;

    // 2. YARDIMCI FONKSİYONLAR
    function updatePriceDisplay(amount, target, bidderName) {
        const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`;
        const el = document.getElementById(id);
        if (el) {
            el.innerText = amount;
            el.classList.remove("blink-anim");
            void el.offsetWidth;
            el.classList.add("blink-anim");
        }
        const leaderRowId = target === 'broadcast' ? 'leader-display-broadcast' : `leader-display-${target}`;
        const leaderRow = document.getElementById(leaderRowId);
        if (leaderRow) {
            if (bidderName) {
                leaderRow.style.display = 'flex';
                leaderRow.querySelector('.name').innerText = bidderName;
            } else {
                leaderRow.style.display = 'none';
            }
        }
    }

    // 3. SOCKET BAĞLANTISI
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let sName = target === 'broadcast' ? CONFIG.username : target;
        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${sName}`);
        window.CURRENT_SOCKET = ws;

        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);
            if (d.type === 'init') { updatePriceDisplay(d.price, target, d.leader); return; }
            if (d.type === 'auction_state') {
                const layer = document.getElementById(target === 'broadcast' ? '' : `bid-layer-${target}`);
                const board = document.getElementById(target === 'broadcast' ? '' : `price-board-${target}`);
                if (layer) layer.style.display = d.active ? 'flex' : 'none';
                if (board) board.style.display = d.active ? 'flex' : 'none';
                return;
            }
            if (d.type === 'reset_auction') {
                updatePriceDisplay(0, target, null);
                const bidFeed = document.getElementById(target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`);
                if (bidFeed) bidFeed.innerHTML = '';
                return;
            }
            if (d.type === 'gift') { showGiftAnimation(d.gift_type, d.sender); return; }
            if (d.type === 'count') {
                const cId = target === 'broadcast' ? 'live-count-broadcast' : `live-count-${target}`;
                const cEl = document.getElementById(cId);
                if (cEl) cEl.innerText = d.val;
                return;
            }
            // Mesajlar
            const feedId = target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`;
            const feed = document.getElementById(feedId);
            if (d.type === 'chat') {
                if (d.msg.startsWith("BID:")) {
                    const amount = d.msg.split(":")[1];
                    updatePriceDisplay(amount, target, d.user);
                    const bidFeedId = target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`;
                    const bidFeed = document.getElementById(bidFeedId);
                    if (bidFeed) {
                        const div = document.createElement('div');
                        div.className = 'bid-bubble';
                        div.innerHTML = `<span class="bidder">${d.user}</span> ₺${amount}`;
                        bidFeed.appendChild(div);
                        bidFeed.scrollTop = bidFeed.scrollHeight;
                        setTimeout(() => { div.remove(); }, 10000);
                    }
                } else {
                    if (feed) {
                        const div = document.createElement('div');
                        div.className = 'msg fade-out';
                        div.innerHTML = `<b>${d.user}:</b> ${d.msg}`;
                        div.addEventListener('animationend', () => div.remove());
                        feed.appendChild(div);
                        feed.scrollTop = feed.scrollHeight;
                    }
                }
            }
        };
    }

    // 4. HEDİYE SİSTEMİ
    window.openGiftMenu = function (username) { activeGiftTarget = username; document.getElementById('giftMenu').style.display = 'block'; }
    window.closeGiftMenu = function () { document.getElementById('giftMenu').style.display = 'none'; }
    window.sendGift = function (giftType) {
        if (!activeGiftTarget) return;
        const formData = new FormData();
        formData.append('target_username', activeGiftTarget);
        formData.append('gift_type', giftType);
        fetch('/gift/send', { method: 'POST', body: formData })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    const screenCount = document.getElementById('screen-diamond-count');
                    const menuCount = document.getElementById('menu-diamond-count');
                    if (screenCount) screenCount.innerText = data.new_balance;
                    if (menuCount) menuCount.innerText = data.new_balance;
                    closeGiftMenu();
                } else { alert(data.msg); }
            }).catch(err => console.error(err));
    }
    function showGiftAnimation(giftType, senderName) {
        const layer = document.getElementById('gift-animation-layer');
        if (!layer) return;
        const emojis = { 'rose': '🌹', 'heart': '❤️', 'car': '🏎️', 'rocket': '🚀' };
        const emoji = emojis[giftType] || '🎁';
        const el = document.createElement('div');
        el.className = 'flying-gift';
        el.innerHTML = `${emoji}<div class="gift-sender-label">${senderName}</div>`;
        layer.appendChild(el);
        setTimeout(() => { el.remove(); }, 3000);
    }

    // 5. YAYINCI KODLARI (BROADCAST MODE)
    if (MODE === 'broadcast') {
        const prev = document.getElementById('preview');
        let rec;

        // Cihaz Seçimi
        async function getDevices() {
            try {
                if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                    await navigator.mediaDevices.getUserMedia({ audio: true });
                    const devices = await navigator.mediaDevices.enumerateDevices();
                    const audioSelect = document.getElementById('audioSource');
                    if (audioSelect) {
                        audioSelect.innerHTML = '';
                        devices.filter(d => d.kind === 'audioinput').forEach(d => {
                            const opt = document.createElement('option');
                            opt.value = d.deviceId;
                            opt.text = d.label || `Mikrofon ${audioSelect.length + 1}`;
                            audioSelect.appendChild(opt);
                        });
                    }
                }
            } catch (e) { console.error("Cihaz listeleme hatası:", e); }
        }

        // Önizleme Başlat
        async function initStream(audioDeviceId = null) {
            const constraints = {
                video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
                audio: audioDeviceId ? { deviceId: { exact: audioDeviceId } } : true
            };
            try {
                if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                    const stream = await navigator.mediaDevices.getUserMedia(constraints);
                    window.localStream = stream;
                    if (prev) { prev.srcObject = stream; prev.volume = 0; }
                    if (!audioDeviceId) getDevices();
                } else {
                    console.log("Kamera erişimi (getUserMedia) desteklenmiyor veya HTTPS gerekli.");
                }
            } catch (err) { console.error(err); alert("Kamera Hatası! Lütfen izinleri kontrol edin."); }
        }
        initStream(); // Sayfa açılınca kamera çalışsın (arka planda)

        window.restartStream = function () {
            const audioSelect = document.getElementById('audioSource');
            if (window.localStream) window.localStream.getTracks().forEach(t => t.stop());
            initStream(audioSelect.value);
        }

        // --- BAŞLAT BUTONUNA TIKLAMA OLAYI ---
        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', function () {
                const titleEl = document.getElementById('streamTitle');
                const catEl = document.getElementById('streamCategory');

                if (!titleEl.value.trim()) { alert("Lütfen başlık girin!"); return; }

                const title = titleEl.value;
                const category = catEl.value;

                // Backend'e Kaydet
                const formData = new FormData();
                formData.append('title', title);
                formData.append('category', category);

                fetch('/broadcast/start', { method: 'POST', body: formData })
                    .then(res => res.json())
                    .then(data => {
                        // UI Değişimi
                        document.getElementById('setup-layer').style.display = 'none';
                        document.getElementById('live-ui').style.display = 'flex';
                        const badge = document.getElementById('cat-badge-display');
                        if (badge) badge.innerText = category;

                        // Yayını ve Chat'i Başlat
                        window.connectChat('broadcast');
                        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                        ws.onopen = () => {
                            let opts = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                            if (!MediaRecorder.isTypeSupported(opts.mimeType)) opts = { mimeType: 'video/webm', videoBitsPerSecond: 2500000 };
                            rec = new MediaRecorder(window.localStream, opts);
                            rec.start(500);
                            rec.ondataavailable = e => { if (e.data.size > 0 && ws.readyState === 1) ws.send(e.data); };
                            sendThumbnailSnapshot();
                            window.thumbInterval = setInterval(sendThumbnailSnapshot, 60000);
                        };
                    })
                    .catch(err => { alert("Başlatma hatası: " + err); });
            });
        }

        window.stopBroadcast = function () {
            if (window.thumbInterval) clearInterval(window.thumbInterval);
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };

        window.toggleAuction = function () {
            AUCTION_ACTIVE = !AUCTION_ACTIVE;
            const btn = document.getElementById('btn-auction-toggle');
            const formData = new FormData();
            formData.append('active', AUCTION_ACTIVE);
            fetch('/broadcast/toggle_auction', { method: 'POST', body: formData });

            if (AUCTION_ACTIVE) {
                btn.innerHTML = "🚫 Kapat"; btn.style.background = "rgba(255, 59, 48, 0.4)";
            } else {
                btn.innerHTML = "🔨 Mezat"; btn.style.background = "rgba(255, 255, 255, 0.2)";
            }
        }

        window.openResetModal = function () { document.getElementById('resetModal').style.display = 'flex'; }
        window.closeResetModal = function () { document.getElementById('resetModal').style.display = 'none'; }
        window.confirmReset = function () {
            closeResetModal();
            fetch('/broadcast/reset_auction', { method: 'POST' });
        }

        async function sendThumbnailSnapshot() {
            const video = document.getElementById('preview');
            if (!video) return;
            const canvas = document.createElement('canvas');
            canvas.width = 640; canvas.height = 360;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const dataUrl = canvas.toDataURL('image/jpeg', 0.6);
            try { await fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: dataUrl, timestamp: Date.now() }) }); } catch (err) { }
        }
    } else {
        // --- İZLEYİCİ MANTIĞI ---
        let obs = new IntersectionObserver((entries) => {
            entries.forEach(e => {
                const u = e.target.dataset.username;
                const v = document.getElementById(`video-${u}`);
                if (e.isIntersecting) {
                    const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`;
                    if (Hls.isSupported()) { const h = new Hls(); h.loadSource(src); h.attachMedia(v); h.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play(); })); }
                    else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = src; v.play().catch(() => { v.muted = true; v.play(); }); }
                    window.connectChat(u);
                } else { if (v) v.pause(); }
            });
        }, { threshold: 0.6 });
        document.querySelectorAll('.stream-item').forEach(s => obs.observe(s));
    }

    // Ortak Fonksiyonlar
    window.unmuteVideo = function (u) { const v = document.getElementById(`video-${u}`); if (v) { v.muted = false; v.volume = 1.0; v.parentElement.querySelector('.tap-hint').style.display = 'none'; } }

    window.toggleFollow = function (username) {
        const btn = document.getElementById(`follow-btn-${username}`);
        const formData = new FormData();
        formData.append('username', username);
        fetch('/user/follow', { method: 'POST', body: formData })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'followed') {
                    if (btn) { btn.classList.add('following'); btn.innerText = 'Takip'; }
                } else {
                    if (btn) { btn.classList.remove('following'); btn.innerText = 'Takip Et'; }
                }
            });
    }

    window.sendBid = function (target, amount) {
        const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`;
        const el = document.getElementById(id);
        const currentVal = parseInt(el ? el.innerText.replace('.', '') : "0") || 0;
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${currentVal + amount}`);
    }

    window.sendManualBid = function (target) {
        const inp = document.getElementById(`manual-bid-${target}`);
        const currentPriceEl = document.getElementById(target === 'broadcast' ? 'current-price-display' : `price-${target}`);
        let currentPrice = parseInt(currentPriceEl ? currentPriceEl.innerText.replace(/\./g, '') : "0") || 0;
        if (inp && inp.value) {
            if (parseInt(inp.value) <= currentPrice) {
                alert("Mevcut fiyattan yüksek bir teklif verin!"); return;
            }
            if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${inp.value}`);
            inp.value = "";
        }
    }

    window.sendMsg = function (target) {
        const inpId = target === 'broadcast' ? 'chat-input-broadcast' : `chat-input-${target}`;
        const inp = document.getElementById(inpId);
        if (inp && inp.value.trim()) {
            if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(inp.value);
            inp.value = "";
            inp.focus();
        }
    }
});