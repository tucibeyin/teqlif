document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;
    let auctionState = "stopped";

    // --- YARDIMCILAR ---
    const moneyFormatter = new Intl.NumberFormat('tr-TR');
    window.formatBidInput = function (el) {
        let val = el.value.replace(/\D/g, '');
        if (val) el.value = moneyFormatter.format(parseInt(val));
        else el.value = "";
    };

    window.toggleManualBid = function (username, show) {
        const presets = document.getElementById(`bid-presets-${username}`);
        const manual = document.getElementById(`bid-manual-${username}`);
        if (show) { if (presets) presets.style.display = 'none'; if (manual) manual.style.display = 'flex'; }
        else { if (manual) manual.style.display = 'none'; if (presets) presets.style.display = 'flex'; }
    };

    window.sendManualBid = function (username) {
        const inp = document.getElementById(`inp-manual-${username}`);
        let amount = parseInt(inp.value.replace(/\./g, ''));
        if (amount > 0) { placeBid(username, amount); toggleManualBid(username, false); inp.value = ""; }
    };

    window.sendChat = function (streamUsername) {
        const input = document.getElementById(`chat-input-${streamUsername}`);
        const video = document.getElementById(`video-${streamUsername}`);
        const text = input.value.trim();
        let ws = null;
        if (MODE === 'broadcast') ws = window.broadcastChatWs;
        else if (video && video.wsConnection) ws = video.wsConnection;
        if (text && ws && ws.readyState === 1) {
            ws.send(JSON.stringify({ type: "chat_message", user: CONFIG.username, text: text }));
            input.value = "";
        }
    };

    window.sendGift = function (targetUser) {
        const btn = document.activeElement;
        if (btn) { btn.style.transform = "scale(0.8)"; setTimeout(() => btn.style.transform = "scale(1)", 100); }
        fetch('/gift/send', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ to_user: targetUser, gift_type: 'diamond' })
        });
    };

    window.toggleAuction = function (username) {
        const btn = document.getElementById('btn-auc-toggle');
        const action = (auctionState === "stopped") ? "start" : "stop";
        fetch('/broadcast/toggle_auction', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: action }) });
        if (MODE === 'broadcast') {
            auctionState = (action === 'start') ? "started" : "stopped";
            btn.innerHTML = (auctionState === 'started') ? "BİTİR" : "BAŞLAT";
            btn.style.background = (auctionState === 'started') ? "#ff3b30" : "#00e676";
            btn.style.color = (auctionState === 'started') ? "white" : "black";
        }
    };

    window.resetAuction = function (username) {
        fetch('/broadcast/reset_auction', { method: 'POST' });
    };

    window.placeBid = function (broadcaster, amount) { fetch('/broadcast/bid', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ broadcaster: broadcaster, amount: amount }) }); };

    function updateAuctionUI(username, data) {
        const bar = document.getElementById(`auction-bar-${username}`);
        const priceEl = document.querySelector(`#auction-bar-${username} .auc-price`);
        const bidderEl = document.querySelector(`#auction-bar-${username} .auc-bidder-name`);

        if (MODE !== 'broadcast') {
            if (data.type === 'auction_started') { bar.style.display = 'flex'; priceEl.innerHTML = `${moneyFormatter.format(data.price)} ₺`; bidderEl.innerText = "Bekleniyor"; }
            else if (data.type === 'auction_ended') { bar.style.display = 'none'; }
        }
        if (data.type === 'auction_started' || data.type === 'auction_update') {
            if (MODE !== 'broadcast' && bar.style.display === 'none') { bar.style.display = 'flex'; }
            priceEl.innerHTML = `${moneyFormatter.format(data.price)} ₺`;
            priceEl.style.color = '#00ff00'; setTimeout(() => priceEl.style.color = '#fff', 300);
            bidderEl.innerText = (data.bidder && data.bidder !== '-') ? data.bidder : "Bekleniyor";
        }
    }

    function addChatMessage(username, user, text) {
        const box = document.getElementById(`chat-box-${username}`);
        if (!box) return;
        const p = document.createElement('div'); p.className = 'chat-msg';
        p.innerHTML = `<span class="chat-user">${user}:</span>${text}`;
        box.appendChild(p); box.scrollTop = box.scrollHeight;
    }

    function updateViewerCount(username, count) {
        const el = document.getElementById(`view-count-${username}`);
        if (el) el.innerText = count;
    }

    function showGiftAnimation(username, sender) {
        const layer = document.getElementById(`gift-layer-${username}`);
        if (!layer) return;
        const el = document.createElement('div'); el.className = 'gift-pop'; el.innerHTML = '💎';
        layer.appendChild(el);
        addChatMessage(username, 'SİSTEM', `💎 ${sender} elmas gönderdi!`);
        setTimeout(() => el.remove(), 2000);
    }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        let broadcastWs = null; let rec = null;

        // 🔥 SESİ AKTİF ET: echoCancellation ve noiseSuppression 🔥
        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user' }
                });
                videoElement.srcObject = stream;
                // Yayıncı kendi sesini duymasın (yankı yapar)
                videoElement.muted = true;
            } catch (e) { alert("Kamera/Mikrofon izni gerekli!"); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData(); fd.append('title', document.getElementById('streamTitle').value); fd.append('category', document.getElementById('streamCategory').value);
            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) return;
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'block';
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    // Tarayıcı destekliyorsa H264 (daha iyi ses senkronu), yoksa VP8
                    let options = { mimeType: 'video/webm;codecs=h264,opus', videoBitsPerSecond: 2500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm;codecs=vp8,opus', videoBitsPerSecond: 2500000 };

                    try { rec = new MediaRecorder(videoElement.srcObject, options); } catch (e) { rec = new MediaRecorder(videoElement.srcObject); }
                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(250);
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = document.getElementById('broadcast-canvas').getContext('2d'); ctx.drawImage(videoElement, 0, 0, 720, 1280);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: document.getElementById('broadcast-canvas').toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };
                broadcastWs.onclose = () => { if (!isIntentionalStop) { if (rec) rec.stop(); alert("Kesildi!"); location.href = '/'; } };

                window.broadcastChatWs = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${CONFIG.username}`);
                window.broadcastChatWs.onmessage = (e) => {
                    const d = JSON.parse(e.data);
                    if (d.type === "chat_message") addChatMessage(CONFIG.username, d.user, d.text);
                    else if (d.type.startsWith("auction_")) updateAuctionUI(CONFIG.username, d);
                    else if (d.type === "viewer_update") updateViewerCount(CONFIG.username, d.count);
                    else if (d.type === "gift_received") showGiftAnimation(CONFIG.username, d.sender);
                };
            });
        });
        window.stopBroadcast = () => { isIntentionalStop = true; if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); if (window.broadcastChatWs) window.broadcastChatWs.close(); fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/'); };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch') {
        const activePlayers = {};
        const observer = new IntersectionObserver((entries) => { entries.forEach(entry => { if (entry.isIntersecting) playStream(entry.target.dataset.username, entry.target.querySelector('video')); else stopStream(entry.target.dataset.username, entry.target.querySelector('video')); }); }, { threshold: 0.6 });
        document.querySelectorAll('.feed-item').forEach(item => observer.observe(item));

        function playStream(username, video) {
            const src = `/static/hls/${username}/index.m3u8`;
            if (activePlayers[username]) return;

            // 🔥 TIKLAYINCA SES AÇMA MANTIĞI 🔥
            // Video varsayılan olarak sessiz (muted) başlar.
            video.muted = true;

            video.onclick = () => {
                video.muted = !video.muted;
                if (!video.muted) {
                    // Sesi açtığını belirtmek için (Opsiyonel)
                    // alert("Ses Açıldı 🔊");
                }
            };

            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                activePlayers[username] = hls; hls.loadSource(src); hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    // Promise hatasını yutuyoruz çünkü ilk başta sessiz oynatmak zorunda
                    video.play().catch(() => { });
                });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = src;
                video.addEventListener('loadedmetadata', () => {
                    video.muted = true;
                    video.play().catch(() => { });
                });
            }

            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${username}`);
            ws.onmessage = (e) => {
                const d = JSON.parse(e.data);
                if (d.type === 'stream_ended') { document.getElementById(`end-screen-${username}`).style.display = 'flex'; stopStream(username, video); }
                else if (d.type === 'chat_message') addChatMessage(username, d.user, d.text);
                else if (d.type.startsWith("auction_")) updateAuctionUI(username, d);
                else if (d.type === "viewer_update") updateViewerCount(username, d.count);
                else if (d.type === "gift_received") showGiftAnimation(username, d.sender);
            };
            video.wsConnection = ws;
        }
        function stopStream(username, video) { if (activePlayers[username]) { activePlayers[username].destroy(); delete activePlayers[username]; } video.pause(); video.src = ""; if (video.wsConnection) { video.wsConnection.close(); delete video.wsConnection; } }
    }
});