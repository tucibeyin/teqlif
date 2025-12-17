document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    let AUCTION_ACTIVE = CONFIG.auctionActive;
    let activeGiftTarget = null;

    // --- FİYAT VE LİDER GÜNCELLEME ---
    function updatePriceDisplay(amount, target, bidderName) {
        const idHost = 'current-price-display';
        const idViewer = `price-${target}`;

        let el = document.getElementById(idHost);
        if (!el) el = document.getElementById(idViewer);

        if (el) {
            el.innerText = amount;
            el.classList.remove("blink-anim");
            void el.offsetWidth; el.classList.add("blink-anim");
        }

        const lHost = 'leader-display-broadcast';
        const lViewer = `leader-display-${target}`;
        let lRow = document.getElementById(lHost);
        // 🔥 DÜZELTME BURADA YAPILDI (lIdViewer -> lViewer) 🔥
        if (!lRow) lRow = document.getElementById(lViewer);

        if (lRow) {
            if (bidderName) {
                lRow.style.display = 'flex';
                lRow.querySelector('.name').innerText = bidderName;
            } else {
                lRow.style.display = 'none';
            }
        }
    }

    // --- SOCKET ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;

        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        window.CURRENT_SOCKET = ws;

        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);

            // Yayın Bitti mi?
            if (d.type === 'stream_ended') { showStreamEndedModal(); return; }

            // İzleyici Sayısı
            if (d.type === 'count') {
                const elBroadcast = document.getElementById('live-count-broadcast');
                const elViewer = document.getElementById(`live-count-${target}`);
                if (elBroadcast) elBroadcast.innerText = d.val;
                if (elViewer) elViewer.innerText = d.val;
                return;
            }

            if (d.type === 'init') { updatePriceDisplay(d.price, target, d.leader); return; }

            if (d.type === 'auction_state') {
                const layer = document.getElementById(`bid-layer-${target}`);
                const board = document.getElementById(`price-board-${target}`);
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
                        div.className = 'msg';
                        div.innerHTML = `<b>${d.user}:</b> ${d.msg}`;
                        feed.appendChild(div);
                        feed.scrollTop = feed.scrollHeight;
                        setTimeout(() => {
                            div.classList.add('fade-out');
                            div.addEventListener('animationend', () => div.remove());
                        }, 5000);
                    }
                }
            }
        };
    }

    function showStreamEndedModal() {
        const modal = document.createElement('div');
        modal.style.position = 'fixed'; modal.style.top = '0'; modal.style.left = '0';
        modal.style.width = '100%'; modal.style.height = '100%';
        modal.style.background = 'rgba(0,0,0,0.85)'; modal.style.backdropFilter = 'blur(10px)';
        modal.style.zIndex = '9999'; modal.style.display = 'flex'; modal.style.flexDirection = 'column';
        modal.style.alignItems = 'center'; modal.style.justifyContent = 'center'; modal.style.color = 'white';
        modal.innerHTML = `<div style="font-size: 60px; margin-bottom: 20px;">🛑</div><h2 style="margin-bottom: 10px;">Yayın Sona Erdi</h2><a href="/" style="background: #34C759; color: black; padding: 12px 30px; border-radius: 20px; text-decoration: none; font-weight: bold;">Ana Sayfaya Dön</a>`;
        document.body.appendChild(modal);
    }

    // Ortak
    window.openGiftMenu = function (username) { activeGiftTarget = username; document.getElementById('giftMenu').style.display = 'block'; }
    window.closeGiftMenu = function () { document.getElementById('giftMenu').style.display = 'none'; }
    window.sendGift = function (giftType) {
        if (!activeGiftTarget) return;
        const formData = new FormData();
        formData.append('target_username', activeGiftTarget);
        formData.append('gift_type', giftType);
        fetch('/gift/send', { method: 'POST', body: formData }).then(res => res.json()).then(data => {
            if (data.status === 'success') {
                document.querySelectorAll('.info-pill.diamond span, #menu-diamond-count, #screen-diamond-count').forEach(el => el.innerText = data.new_balance);
                closeGiftMenu();
            } else { alert(data.msg); }
        });
    }
    function showGiftAnimation(giftType, senderName) {
        const layer = document.getElementById('gift-animation-layer');
        if (!layer) return;
        const emojis = { 'rose': '🌹', 'heart': '❤️', 'car': '🏎️', 'rocket': '🚀' };
        const el = document.createElement('div');
        el.className = 'flying-gift';
        el.innerHTML = `${emojis[giftType] || '🎁'}<div class="gift-sender-label">${senderName}</div>`;
        layer.appendChild(el);
        setTimeout(() => { el.remove(); }, 3000);
    }

    if (MODE === 'broadcast') {
        const prev = document.getElementById('preview');
        let rec;
        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720 }, audio: true });
                window.localStream = stream;
                if (prev) { prev.srcObject = stream; prev.volume = 0; }
                const devices = await navigator.mediaDevices.enumerateDevices();
                const audioSelect = document.getElementById('audioSource');
                if (audioSelect) {
                    audioSelect.innerHTML = '';
                    devices.filter(d => d.kind === 'audioinput').forEach(d => {
                        const opt = document.createElement('option');
                        opt.value = d.deviceId; opt.text = d.label || 'Mikrofon';
                        audioSelect.appendChild(opt);
                    });
                }
            } catch (err) { console.error(err); alert("Kamera Hatası!"); }
        }
        initStream();
        window.restartStream = function () { if (window.localStream) window.localStream.getTracks().forEach(t => t.stop()); initStream(); }
        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', function () {
                const title = document.getElementById('streamTitle').value;
                const category = document.getElementById('streamCategory').value;
                if (!title) { alert("Başlık girin!"); return; }
                const formData = new FormData(); formData.append('title', title); formData.append('category', category);
                fetch('/broadcast/start', { method: 'POST', body: formData }).then(res => res.json()).then(data => {
                    document.getElementById('setup-layer').style.display = 'none';
                    document.getElementById('live-ui').style.display = 'flex';
                    window.connectChat('broadcast');
                    const ws = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                    ws.onopen = () => {
                        let mimeType = 'video/webm;codecs=vp9';
                        if (!MediaRecorder.isTypeSupported(mimeType)) {
                            mimeType = 'video/webm;codecs=vp8'; // Android için en güvenli liman
                            if (!MediaRecorder.isTypeSupported(mimeType)) {
                                mimeType = 'video/webm'; // Tarayıcı ne istiyorsa o olsun
                            }
                        }

                        let opts = { mimeType: mimeType, videoBitsPerSecond: 2500000 };
                        console.log("Seçilen Format:", mimeType);
                        rec = new MediaRecorder(window.localStream, opts);
                        rec.start(500);
                        rec.ondataavailable = e => { if (e.data.size > 0 && ws.readyState === 1) ws.send(e.data); };
                        sendThumbnailSnapshot();
                        window.thumbInterval = setInterval(sendThumbnailSnapshot, 60000);
                    };
                });
            });
        }
        window.stopBroadcast = function () { if (window.thumbInterval) clearInterval(window.thumbInterval); fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/'; };
        window.toggleAuction = function () {
            AUCTION_ACTIVE = !AUCTION_ACTIVE;
            const btn = document.getElementById('btn-auction-toggle');
            const formData = new FormData(); formData.append('active', AUCTION_ACTIVE);
            fetch('/broadcast/toggle_auction', { method: 'POST', body: formData });
            if (AUCTION_ACTIVE) { btn.innerHTML = "🚫 Kapat"; btn.style.background = "rgba(255, 59, 48, 0.4)"; }
            else { btn.innerHTML = "🔨 Mezat"; btn.style.background = "rgba(255, 255, 255, 0.2)"; }
        }
        window.openResetModal = function () { document.getElementById('resetModal').style.display = 'flex'; }
        window.closeResetModal = function () { document.getElementById('resetModal').style.display = 'none'; }
        window.confirmReset = function () { closeResetModal(); fetch('/broadcast/reset_auction', { method: 'POST' }); }
        async function sendThumbnailSnapshot() {
            const video = document.getElementById('preview');
            const canvas = document.createElement('canvas'); canvas.width = 640; canvas.height = 360;
            canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
            try { await fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.6), timestamp: Date.now() }) }); } catch (err) { }
        }
    } else {
        let obs = new IntersectionObserver((entries) => {
            entries.forEach(e => {
                const u = e.target.dataset.username;
                const v = document.getElementById(`video-${u}`);
                if (e.isIntersecting) {
                    const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`;
                    if (Hls.isSupported()) { const h = new Hls(); h.loadSource(src); h.attachMedia(v); h.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() })); }
                    else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = src; v.play().catch(() => { v.muted = true; v.play() }); }
                    window.connectChat(u);
                } else { if (v) v.pause(); }
            });
        }, { threshold: 0.6 });
        document.querySelectorAll('.stream-item').forEach(s => obs.observe(s));
    }
    window.unmuteVideo = function (u) { const v = document.getElementById(`video-${u}`); if (v) { v.muted = false; v.volume = 1.0; v.parentElement.querySelector('.tap-hint').style.display = 'none'; } }
    window.toggleFollow = function (username) { const btn = document.getElementById(`follow-btn-${username}`); const formData = new FormData(); formData.append('username', username); fetch('/user/follow', { method: 'POST', body: formData }).then(res => res.json()).then(data => { if (data.status === 'followed') { if (btn) { btn.classList.add('following'); btn.innerText = '✓'; } } else { if (btn) { btn.classList.remove('following'); btn.innerText = '+'; } } }); }
    window.sendBid = function (target, amount) { const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`; const el = document.getElementById(id); const currentVal = parseInt(el ? el.innerText.replace('.', '') : "0") || 0; if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${currentVal + amount}`); }
    window.sendManualBid = function (target) { const inp = document.getElementById(`manual-bid-${target}`); if (inp && inp.value) { window.CURRENT_SOCKET.send(`BID:${inp.value}`); inp.value = ""; } }
    window.sendMsg = function (target) { const inpId = target === 'broadcast' ? 'chat-input-broadcast' : `chat-input-${target}`; const inp = document.getElementById(inpId); if (inp && inp.value.trim()) { window.CURRENT_SOCKET.send(inp.value); inp.value = ""; inp.focus(); } }
});