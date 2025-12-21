document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;

    // CHAT GÖNDERME FONKSİYONU (Global erişim için window'a atadık)
    window.sendChat = function (streamUsername) {
        const input = document.getElementById(`chat-input-${streamUsername}`);
        const video = document.getElementById(`video-${streamUsername}`);
        const text = input.value.trim();

        if (text && video && video.dataset.ws) {
            const ws = video.dataset.ws; // O videonun soketini bul
            // Eğer soket nesnesi WebSocket değilse (nesne olarak saklanmışsa) .send metodunu çağır
            if (ws.send) {
                ws.send(JSON.stringify({
                    type: "chat_message",
                    user: CONFIG.username,
                    text: text
                }));
            }
            input.value = ""; // Kutuyu temizle
        }
    };

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let chatWs = null; // Yayıncının kendi chat'ini dinlemesi için

        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user' }
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

                // 1. YAYIN SOCKETİ
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const cameraStream = videoElement.srcObject;
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };

                    try { rec = new MediaRecorder(cameraStream, options); } catch (e) { rec = new MediaRecorder(cameraStream); }
                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(1000);

                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            const vW = videoElement.videoWidth; const vH = videoElement.videoHeight;
                            const targetRatio = 9 / 16; let sW, sH, sX, sY;
                            if (vW / vH > targetRatio) { sH = vH; sW = vH * targetRatio; sX = (vW - sW) / 2; sY = 0; }
                            else { sW = vW; sH = vW / targetRatio; sX = 0; sY = (vH - sH) / 2; }
                            ctx.drawImage(videoElement, sX, sY, sW, sH, 0, 0, canvas.width, canvas.height);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };
                broadcastWs.onclose = () => { if (!isIntentionalStop) { if (rec) rec.stop(); alert("Kesildi!"); location.href = '/'; } };

                // 2. CHAT SOCKETİ (Yayıncı da mesajları görmeli)
                chatWs = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${CONFIG.username}`);
                chatWs.onmessage = (e) => {
                    const d = JSON.parse(e.data);
                    if (d.type === "chat_message") {
                        const box = document.getElementById(`chat-box-${CONFIG.username}`);
                        const p = document.createElement('div');
                        p.className = 'chat-msg';
                        p.innerHTML = `<span class="chat-user">${d.user}:</span><span class="chat-text">${d.text}</span>`;
                        box.appendChild(p);
                        box.scrollTop = box.scrollHeight;
                    }
                };

            });
        });

        window.stopBroadcast = () => {
            isIntentionalStop = true;
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); if (chatWs) chatWs.close();
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/');
        };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch') {
        const activePlayers = {};

        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                const container = entry.target;
                const username = container.dataset.username;
                const video = container.querySelector('video');

                if (entry.isIntersecting) {
                    playStream(username, video);
                } else {
                    stopStream(username, video);
                }
            });
        }, { threshold: 0.6 });

        document.querySelectorAll('.feed-item').forEach(item => observer.observe(item));

        function playStream(username, video) {
            const src = `/static/hls/${username}/index.m3u8`;
            if (activePlayers[username]) return; // Zaten açıksa elleme

            // HLS Başlat
            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                activePlayers[username] = hls;
                hls.loadSource(src);
                hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, () => { video.muted = true; video.play().catch(() => { }); });
                hls.on(Hls.Events.ERROR, (e, d) => { if (d.fatal && d.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad(); else if (d.fatal) hls.destroy(); });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = src;
                video.addEventListener('loadedmetadata', () => { video.muted = true; video.play().catch(() => { }); });
                video.addEventListener('error', () => setTimeout(() => { video.src = src; video.load(); }, 2000));
            }

            // Chat Socket Bağlantısı
            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${username}`);
            ws.onmessage = (e) => {
                const d = JSON.parse(e.data);
                if (d.type === 'stream_ended') {
                    document.getElementById(`end-screen-${username}`).style.display = 'flex';
                    stopStream(username, video);
                }
                else if (d.type === 'chat_message') {
                    const box = document.getElementById(`chat-box-${username}`);
                    const p = document.createElement('div');
                    p.className = 'chat-msg';
                    p.innerHTML = `<span class="chat-user">${d.user}:</span><span class="chat-text">${d.text}</span>`;
                    box.appendChild(p);
                    box.scrollTop = box.scrollHeight; // Auto scroll
                }
            };
            video.dataset.ws = ws; // WS nesnesini sakla (mesaj atmak için)
            // WS nesnesinin send metodunu doğrudan dataset'e atayamayız, nesneyi JS memory'de tutuyoruz
            // Send fonksiyonu yukarıda video.dataset.ws üzerinden WS'ye erişecek.
            // Not: dataset string tutar, bu yüzden activePlayers gibi bir obje kullanalım veya element property
            video.dataset.ws = "connected"; // Flag
            video.wsConnection = ws; // Direct property assignment
        }

        // Global sendChat fonksiyonunu düzelt (Dataset değil property kullan)
        window.sendChat = function (streamUsername) {
            const input = document.getElementById(`chat-input-${streamUsername}`);
            const video = document.getElementById(`video-${streamUsername}`);
            const text = input.value.trim();

            if (text && video && video.wsConnection && video.wsConnection.readyState === 1) {
                video.wsConnection.send(JSON.stringify({
                    type: "chat_message",
                    user: CONFIG.username,
                    text: text
                }));
                input.value = "";
            }
        };

        function stopStream(username, video) {
            if (activePlayers[username]) {
                activePlayers[username].destroy();
                delete activePlayers[username];
            }
            video.pause();
            video.src = "";
            if (video.wsConnection) {
                video.wsConnection.close();
                delete video.wsConnection;
            }
        }
    }
});