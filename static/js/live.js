document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;

    // --- GLOBAL İŞLEVLER ---
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
        fetch('/gift/send', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ to_user: targetUser, gift_type: 'diamond' })
        });
    };

    // 🔥 MEZAT İŞLEVLERİ 🔥
    window.toggleAuction = function (username, action) {
        // Eğer action verilmezse, açık olanı kapat (Stop)
        const act = action || "stop";
        fetch('/broadcast/toggle_auction', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: act })
        });

        if (MODE === 'broadcast') {
            const startBtn = document.getElementById('btn-start-auction');
            const panel = document.getElementById(`auction-panel-${username}`);
            if (act === 'start') {
                startBtn.style.display = 'none';
                panel.style.display = 'flex';
            } else {
                startBtn.style.display = 'block';
                panel.style.display = 'none';
            }
        }
    };

    window.placeBid = function (broadcaster, amount) {
        fetch('/broadcast/bid', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ broadcaster: broadcaster, amount: amount })
        });
    };

    function updateAuctionUI(username, data) {
        const panel = document.getElementById(`auction-panel-${username}`);
        const priceEl = document.getElementById(`auc-price-${username}`);
        const bidderEl = document.getElementById(`auc-bidder-${username}`);

        if (data.type === 'auction_started') {
            panel.style.display = 'flex';
            priceEl.innerText = `${data.price} ₺`;
            bidderEl.innerText = "Son Teklif: -";
        } else if (data.type === 'auction_update') {
            panel.style.display = 'flex';
            priceEl.innerText = `${data.price} ₺`;
            // Yanıp sönme efekti
            priceEl.style.color = '#00ff00';
            setTimeout(() => priceEl.style.color = 'black', 300);
            bidderEl.innerText = `Son Teklif: ${data.bidder}`;
        } else if (data.type === 'auction_ended') {
            panel.style.display = 'none';
        }
    }

    function showGiftAnimation(username, sender) {
        const layer = document.getElementById(`gift-layer-${username}`);
        if (!layer) return;
        const el = document.createElement('div'); el.className = 'gift-pop'; el.innerHTML = '💎';
        layer.appendChild(el);
        // Chat'e ekle
        addChatMessage(username, 'SİSTEM', `💎 ${sender} elmas gönderdi!`, true);
        setTimeout(() => el.remove(), 1500);
    }

    function addChatMessage(username, user, text, isSystem = false) {
        const box = document.getElementById(`chat-box-${username}`);
        if (!box) return;

        const p = document.createElement('div');
        p.className = isSystem ? 'chat-msg sys-msg' : 'chat-msg';
        p.innerHTML = `<span class="chat-user">${user}:</span><span class="chat-text">${text}</span>`;
        box.appendChild(p); box.scrollTop = box.scrollHeight;

        // 🔥 5 SANİYE KURALI (Mesaj Silme) 🔥
        setTimeout(() => {
            p.style.opacity = '0'; // Önce soldur
            setTimeout(() => p.remove(), 500); // Sonra sil
        }, 5000);
    }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        let broadcastWs = null; let rec = null;

        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true }, video: { facingMode: 'user' }
                });
                videoElement.srcObject = stream;
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Live');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { alert("Hata!"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const cameraStream = videoElement.srcObject;
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };
                    try { rec = new MediaRecorder(cameraStream, options); } catch (e) { rec = new MediaRecorder(cameraStream); }
                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(250);
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = document.getElementById('broadcast-canvas').getContext('2d');
                            const vW = videoElement.videoWidth; const vH = videoElement.videoHeight;
                            const targetRatio = 9 / 16; let sW, sH, sX, sY;
                            if (vW / vH > targetRatio) { sH = vH; sW = vH * targetRatio; sX = (vW - sW) / 2; sY = 0; }
                            else { sW = vW; sH = vW / targetRatio; sX = 0; sY = (vH - sH) / 2; }
                            ctx.drawImage(videoElement, sX, sY, sW, sH, 0, 0, 720, 1280);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: document.getElementById('broadcast-canvas').toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };
                broadcastWs.onclose = () => { if (!isIntentionalStop) { if (rec) rec.stop(); alert("Kesildi!"); location.href = '/'; } };

                window.broadcastChatWs = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${CONFIG.username}`);
                window.broadcastChatWs.onmessage = (e) => {
                    const d = JSON.parse(e.data);
                    if (d.type === "chat_message") addChatMessage(CONFIG.username, d.user, d.text);
                    else if (d.type === "gift_received") showGiftAnimation(CONFIG.username, d.sender);
                    else if (d.type.startsWith("auction_")) updateAuctionUI(CONFIG.username, d); // Mezat
                };
            });
        });

        window.stopBroadcast = () => {
            isIntentionalStop = true;
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); if (window.broadcastChatWs) window.broadcastChatWs.close();
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/');
        };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch') {
        const activePlayers = {};
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) playStream(entry.target.dataset.username, entry.target.querySelector('video'));
                else stopStream(entry.target.dataset.username, entry.target.querySelector('video'));
            });
        }, { threshold: 0.6 });
        document.querySelectorAll('.feed-item').forEach(item => observer.observe(item));

        function playStream(username, video) {
            const src = `/static/hls/${username}/index.m3u8`;
            if (activePlayers[username]) return;
            video.onclick = () => { video.muted = !video.muted; };

            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true, liveSyncDurationCount: 3, liveMaxLatencyDurationCount: 5, maxLiveSyncPlaybackRate: 1.5 });
                activePlayers[username] = hls;
                hls.loadSource(src); hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, () => { video.muted = true; video.play().catch(() => { }); });
                hls.on(Hls.Events.ERROR, (e, d) => { if (d.fatal && d.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad(); });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = src; video.addEventListener('loadedmetadata', () => { video.muted = true; video.play().catch(() => { }); });
            }

            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${username}`);
            ws.onmessage = (e) => {
                const d = JSON.parse(e.data);
                if (d.type === 'stream_ended') { document.getElementById(`end-screen-${username}`).style.display = 'flex'; stopStream(username, video); }
                else if (d.type === 'chat_message') addChatMessage(username, d.user, d.text);
                else if (d.type === 'gift_received') showGiftAnimation(username, d.sender);
                else if (d.type.startsWith("auction_")) updateAuctionUI(username, d); // Mezat
            };
            video.wsConnection = ws;
        }

        function stopStream(username, video) {
            if (activePlayers[username]) { activePlayers[username].destroy(); delete activePlayers[username]; }
            video.pause(); video.src = "";
            if (video.wsConnection) { video.wsConnection.close(); delete video.wsConnection; }
        }
    }
});