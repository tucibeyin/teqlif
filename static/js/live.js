document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    window.activeHlsInstances = {};
    let AUCTION_ACTIVE = CONFIG.auctionActive;
    let activeModTarget = null;

    let videoDevices = [];
    let currentDeviceIndex = 0;
    let canvas, ctx, animationFrameId;
    let localStream = null;
    let rec = null;
    let broadcastWs = null;

    // --- 1. UI/MODERASYON ---
    window.openModMenu = function (username) {
        if (MODE === 'broadcast' && username !== CONFIG.username) {
            activeModTarget = username;
            document.getElementById('mod-target-name').innerText = username;
            document.getElementById('modMenu').style.display = 'flex';
        }
    }
    window.closeModMenu = function () { document.getElementById('modMenu').style.display = 'none'; activeModTarget = null; }
    window.restrictUser = function (action, duration = 0) {
        if (!activeModTarget) return;
        const formData = new FormData();
        formData.append('target_username', activeModTarget); formData.append('action', action); formData.append('duration', duration);
        fetch('/stream/restrict', { method: 'POST', body: formData }).then(res => res.json()).then(data => { alert(data.msg); closeModMenu(); });
    }

    function updatePriceDisplay(amount, target, bidderName) {
        const idHost = 'current-price-display'; const idViewer = `price-${target}`;
        let el = document.getElementById(idHost); if (!el) el = document.getElementById(idViewer);
        if (el) { el.innerText = amount; el.classList.remove("blink-anim"); void el.offsetWidth; el.classList.add("blink-anim"); }
        const lHost = 'leader-display-broadcast'; const lViewer = `leader-display-${target}`;
        let lRow = document.getElementById(lHost); if (!lRow) lRow = document.getElementById(lViewer);
        if (lRow) { if (bidderName) { lRow.style.display = 'flex'; lRow.querySelector('.name').innerText = bidderName; } else { lRow.style.display = 'none'; } }
    }

    // --- 2. SOHBET ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        const chatWs = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        window.CURRENT_SOCKET = chatWs;
        chatWs.onmessage = (e) => {
            const d = JSON.parse(e.data);
            if (d.type === 'banned') { alert("🔴 Yasaklandınız!"); window.location.href = "/"; return; }
            if (d.type === 'alert') { alert(d.msg); return; }
            if (d.type === 'stream_ended') { showStreamEndedModal(); return; }
            if (d.type === 'count') {
                const elBroadcast = document.getElementById('live-count-broadcast'); const elViewer = document.getElementById(`live-count-${target}`);
                if (elBroadcast) elBroadcast.innerText = d.val; if (elViewer) elViewer.innerText = d.val; return;
            }
            if (d.type === 'init') { updatePriceDisplay(d.price, target, d.leader); return; }
            if (d.type === 'auction_state') {
                const layer = document.getElementById(`bid-layer-${target}`); const board = document.getElementById(`price-board-${target}`);
                if (layer) layer.style.display = d.active ? 'flex' : 'none'; if (board) board.style.display = d.active ? 'flex' : 'none'; return;
            }
            if (d.type === 'reset_auction') {
                updatePriceDisplay(0, target, null);
                const bidFeed = document.getElementById(target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`);
                if (bidFeed) bidFeed.innerHTML = ''; return;
            }
            if (d.type === 'gift') { showGiftAnimation(d.gift_type, d.sender); return; }

            const feedId = target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`;
            const feed = document.getElementById(feedId);
            if (d.type === 'chat') {
                if (d.msg.startsWith("BID:")) {
                    const amount = d.msg.split(":")[1]; updatePriceDisplay(amount, target, d.user);
                    const bidFeedId = target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`;
                    const bidFeed = document.getElementById(bidFeedId);
                    if (bidFeed) { const div = document.createElement('div'); div.className = 'bid-bubble'; div.innerHTML = `<span class="bidder">${d.user}</span> ₺${amount}`; bidFeed.appendChild(div); bidFeed.scrollTop = bidFeed.scrollHeight; setTimeout(() => { div.remove(); }, 10000); }
                } else {
                    if (feed) { const div = document.createElement('div'); div.className = 'msg'; div.innerHTML = `<b onclick="openModMenu('${d.user}')" style="cursor:pointer;">${d.user}:</b> ${d.msg}`; feed.appendChild(div); feed.scrollTop = feed.scrollHeight; setTimeout(() => { div.classList.add('fade-out'); setTimeout(() => div.remove(), 1000); }, 5000); }
                }
            }
        };
    }

    function showStreamEndedModal() {
        if (document.getElementById('stream-ended-modal')) return;
        const modal = document.createElement('div'); modal.id = 'stream-ended-modal';
        Object.assign(modal.style, { position: 'fixed', top: '0', left: '0', width: '100%', height: '100%', background: 'rgba(0,0,0,0.85)', backdropFilter: 'blur(10px)', zIndex: '9999', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: 'white' });
        modal.innerHTML = `<div style="font-size: 60px; margin-bottom: 20px;">🛑</div><h2 style="margin-bottom: 10px;">Yayın Sona Erdi</h2><a href="/" style="background: #34C759; color: black; padding: 12px 30px; border-radius: 20px; text-decoration: none; font-weight: bold;">Ana Sayfaya Dön</a>`;
        document.body.appendChild(modal);
    }

    window.openGiftMenu = function (username) { document.getElementById('giftMenu').style.display = 'block'; }
    window.closeGiftMenu = function () { document.getElementById('giftMenu').style.display = 'none'; }
    window.sendGift = function (giftType) {
        let target = CONFIG.username === CONFIG.broadcaster ? activeModTarget : CONFIG.broadcaster;
        if (!target) target = CONFIG.broadcaster;
        if (!target) return;
        const formData = new FormData(); formData.append('target_username', target); formData.append('gift_type', giftType);
        fetch('/gift/send', { method: 'POST', body: formData }).then(res => res.json()).then(data => { if (data.status === 'success') { document.querySelectorAll('.info-pill.diamond span, #menu-diamond-count, #screen-diamond-count').forEach(el => el.innerText = data.new_balance); closeGiftMenu(); } else { alert(data.msg); } });
    }
    function showGiftAnimation(giftType, senderName) {
        const layer = document.getElementById('gift-animation-layer'); if (!layer) return;
        const emojis = { 'rose': '🌹', 'heart': '❤️', 'car': '🏎️', 'rocket': '🚀' };
        const el = document.createElement('div'); el.className = 'flying-gift'; el.innerHTML = `${emojis[giftType] || '🎁'}<div class="gift-sender-label">${senderName}</div>`;
        layer.appendChild(el); setTimeout(() => { el.remove(); }, 3000);
    }

    // --- 3. YAYINCI (ANDROID WARM-UP FIX) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        canvas = document.getElementById('broadcast-canvas');
        ctx = canvas.getContext('2d', { alpha: false });

        async function getDevices() { try { const devices = await navigator.mediaDevices.enumerateDevices(); videoDevices = devices.filter(d => d.kind === 'videoinput'); } catch (e) { console.log(e); } }
        getDevices();

        async function initStream(deviceId = null) {
            if (localStream) { localStream.getTracks().forEach(track => track.stop()); }
            const constraints = {
                audio: { echoCancellation: true, noiseSuppression: true },
                video: deviceId ? { deviceId: { exact: deviceId }, width: { ideal: 1280 }, height: { ideal: 720 } } : { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }
            };
            try {
                const stream = await navigator.mediaDevices.getUserMedia(constraints);
                localStream = stream; videoElement.srcObject = stream;
                startCanvasLoop();
                const devices = await navigator.mediaDevices.enumerateDevices();
                const audioSelect = document.getElementById('audioSource');
                if (audioSelect && audioSelect.options.length === 0) { devices.filter(d => d.kind === 'audioinput').forEach(d => { const opt = document.createElement('option'); opt.value = d.deviceId; opt.text = d.label || 'Mikrofon'; audioSelect.appendChild(opt); }); }
            } catch (err) { console.error(err); alert("Kamera Hatası! İzinleri kontrol edin."); }
        }
        initStream();

        window.switchCamera = function () { if (videoDevices.length < 2) { alert("Başka kamera bulunamadı."); return; } currentDeviceIndex = (currentDeviceIndex + 1) % videoDevices.length; initStream(videoDevices[currentDeviceIndex].deviceId); }

        function startCanvasLoop() {
            if (animationFrameId) cancelAnimationFrame(animationFrameId);
            function draw() {
                if (videoElement.readyState === videoElement.HAVE_ENOUGH_DATA) {
                    const vRatio = videoElement.videoWidth / videoElement.videoHeight;
                    const cRatio = canvas.width / canvas.height;
                    let drawWidth, drawHeight, startX, startY;
                    if (vRatio > cRatio) { drawHeight = canvas.height; drawWidth = drawHeight * vRatio; startX = (canvas.width - drawWidth) / 2; startY = 0; } else { drawWidth = canvas.width; drawHeight = drawWidth / vRatio; startX = 0; startY = (canvas.height - drawHeight) / 2; }
                    ctx.drawImage(videoElement, startX, startY, drawWidth, drawHeight);
                }
                animationFrameId = requestAnimationFrame(draw);
            }
            draw();
        }
        window.restartStream = function () { initStream(); }

        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', function () {
                const title = document.getElementById('streamTitle').value; const category = document.getElementById('streamCategory').value;
                if (!title) { alert("Başlık girin!"); return; }
                const formData = new FormData(); formData.append('title', title); formData.append('category', category);
                fetch('/broadcast/start', { method: 'POST', body: formData }).then(res => res.json()).then(data => {
                    document.getElementById('setup-layer').style.display = 'none'; document.getElementById('live-ui').style.display = 'flex';
                    if (category !== 'Mezat') {
                        const resetBtn = document.querySelector('button[onclick="openResetModal()"]'); const toggleBtn = document.getElementById('btn-auction-toggle'); const priceBoard = document.querySelector('.top-bar-left .price-board');
                        if (resetBtn) resetBtn.style.display = 'none'; if (toggleBtn) toggleBtn.style.display = 'none'; if (priceBoard) priceBoard.style.display = 'none';
                    }
                    window.connectChat('broadcast');

                    broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                    broadcastWs.onopen = () => {
                        const canvasStream = canvas.captureStream(24);
                        const audioTracks = localStream.getAudioTracks();
                        if (audioTracks.length > 0) canvasStream.addTrack(audioTracks[0]);

                        // 🔥 ANDROID GÜVENLİ FORMAT & BITRATE 🔥
                        let options = { mimeType: 'video/webm', videoBitsPerSecond: 1000000 };
                        if (MediaRecorder.isTypeSupported('video/webm;codecs=vp8')) {
                            options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                        }

                        try { rec = new MediaRecorder(canvasStream, options); } catch (e) { rec = new MediaRecorder(canvasStream); }

                        rec.ondataavailable = e => {
                            if (e.data.size > 0 && broadcastWs.readyState === 1) {
                                broadcastWs.send(e.data);
                            }
                        };

                        // 🔥 ISINMA SÜRESİ (1 Saniye Bekle - Hata Önleyici) 🔥
                        setTimeout(() => {
                            if (rec.state === 'inactive') rec.start(1000);
                        }, 1000);

                        sendThumbnailSnapshot();
                        window.thumbInterval = setInterval(sendThumbnailSnapshot, 60000);
                    };
                });
            });
        }

        window.stopBroadcast = function () {
            if (window.thumbInterval) clearInterval(window.thumbInterval);
            if (animationFrameId) cancelAnimationFrame(animationFrameId);
            if (rec && rec.state !== 'inactive') rec.stop();
            if (localStream) localStream.getTracks().forEach(t => t.stop());
            if (broadcastWs) broadcastWs.close();

            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };

        window.toggleAuction = function () { AUCTION_ACTIVE = !AUCTION_ACTIVE; const btn = document.getElementById('btn-auction-toggle'); const formData = new FormData(); formData.append('active', AUCTION_ACTIVE); fetch('/broadcast/toggle_auction', { method: 'POST', body: formData }); if (AUCTION_ACTIVE) { btn.innerHTML = "🚫 Kapat"; btn.style.background = "rgba(255, 59, 48, 0.4)"; } else { btn.innerHTML = "🔨 Mezat"; btn.style.background = "rgba(255, 255, 255, 0.2)"; } }
        window.openResetModal = function () { document.getElementById('resetModal').style.display = 'flex'; }
        window.closeResetModal = function () { document.getElementById('resetModal').style.display = 'none'; }
        window.confirmReset = function () { closeResetModal(); fetch('/broadcast/reset_auction', { method: 'POST' }); }
        async function sendThumbnailSnapshot() { try { await fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.6), timestamp: Date.now() }) }); } catch (err) { } }
    } else {
        // --- İZLEYİCİ ---
        const hlsConfig = { enableWorker: true, lowLatencyMode: true, backBufferLength: 0, liveSyncDurationCount: 2, liveMaxLatencyDurationCount: 4, maxBufferLength: 3, maxMaxBufferLength: 5, enableSoftwareAES: false, fragLoadingTimeOut: 10000 };

        if (CONFIG.broadcaster && CONFIG.mode === 'watch') {
            const u = CONFIG.broadcaster; const v = document.getElementById(`video-${u}`);
            if (v) {
                const src = `/static/hls/${u}/master.m3u8`;
                if (Hls.isSupported()) { const h = new Hls(hlsConfig); h.loadSource(src); h.attachMedia(v); h.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(e => console.log("Blocked:", e))); }
                else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = src; v.play().catch(e => console.log("Blocked:", e)); }
                window.connectChat(u);
            }
        } else {
            let obs = new IntersectionObserver((entries) => {
                entries.forEach(e => {
                    const u = e.target.dataset.username; const v = document.getElementById(`video-${u}`);
                    if (e.isIntersecting) {
                        if (!window.activeHlsInstances[u] && Hls.isSupported()) {
                            const src = `/static/hls/${u}/master.m3u8`; const h = new Hls(hlsConfig); h.loadSource(src); h.attachMedia(v); h.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));
                            window.activeHlsInstances[u] = h;
                        } else if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = `/static/hls/${u}/master.m3u8`; v.play().catch(() => { v.muted = true; v.play() }); }
                        window.connectChat(u);
                    } else {
                        if (v) v.pause();
                        if (window.activeHlsInstances[u]) { window.activeHlsInstances[u].destroy(); delete window.activeHlsInstances[u]; }
                        if (v.canPlayType('application/vnd.apple.mpegurl')) v.src = "";
                    }
                });
            }, { threshold: 0.5 });
            document.querySelectorAll('.stream-item').forEach(s => obs.observe(s));
        }
    }

    // Ortak
    window.unmuteVideo = function (u) { const v = document.getElementById(`video-${u}`); if (v) { v.muted = false; v.volume = 1.0; v.parentElement.querySelector('.tap-hint').style.display = 'none'; } }
    window.toggleFollow = function (username) { const btn = document.getElementById(`follow-btn-${username}`); const formData = new FormData(); formData.append('username', username); fetch('/user/follow', { method: 'POST', body: formData }).then(res => res.json()).then(data => { if (data.status === 'followed') { if (btn) { btn.classList.add('following'); btn.innerText = '✓'; } } else { if (btn) { btn.classList.remove('following'); btn.innerText = '+'; } } }); }
    window.sendBid = function (target, amount) { const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`; const el = document.getElementById(id); const currentVal = parseInt(el ? el.innerText.replace('.', '') : "0") || 0; if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${currentVal + amount}`); }
    window.sendManualBid = function (target) { const inp = document.getElementById(`manual-bid-${target}`); if (inp && inp.value) { window.CURRENT_SOCKET.send(`BID:${inp.value}`); inp.value = ""; } }
    window.sendMsg = function (target) { const inpId = target === 'broadcast' ? 'chat-input-broadcast' : `chat-input-${target}`; const inp = document.getElementById(inpId); if (inp && inp.value.trim()) { window.CURRENT_SOCKET.send(inp.value); inp.value = ""; inp.focus(); } }
});