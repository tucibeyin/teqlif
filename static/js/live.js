document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // DOĞAL SENSÖR (EN GENİŞ AÇI)
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
                if (!res.ok) { alert("Sunucu Hatası"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    // DİREKT AKIŞ
                    const cameraStream = videoElement.srcObject;

                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };

                    try { rec = new MediaRecorder(cameraStream, options); } catch (e) { rec = new MediaRecorder(cameraStream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // 🔥 KRİTİK DÜZELTME: Veri düşürme (Drop) KALDIRILDI 🔥
                            // Veri bozulursa FFmpeg kilitlenir. Artık her şeyi gönderiyoruz.
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000); // 1 saniyelik paketler

                    // Thumbnail (15sn)
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            const vW = videoElement.videoWidth; const vH = videoElement.videoHeight;
                            const targetRatio = 9 / 16;
                            let sW, sH, sX, sY;
                            if (vW / vH > targetRatio) { sH = vH; sW = vH * targetRatio; sX = (vW - sW) / 2; sY = 0; }
                            else { sW = vW; sH = vW / targetRatio; sX = 0; sY = (vH - sH) / 2; }
                            ctx.drawImage(videoElement, sX, sY, sW, sH, 0, 0, canvas.width, canvas.height);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };
                broadcastWs.onclose = () => {
                    if (!isIntentionalStop) { if (rec) rec.stop(); alert("Yayın Kesildi!"); location.href = '/'; }
                };
            });
        });

        window.stopBroadcast = () => {
            isIntentionalStop = true;
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/');
        };
    }

    // --- İZLEYİCİ (REELS MODU + AUTO PLAY) ---
    else if (MODE === 'watch') {
        const activePlayers = {};

        // GÖZLEMCİ
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
            const src = `/static/hls/${username}/index.m3u8`; // Tekrar index'e döndük (Stabilite için)
            if (activePlayers[username]) return;

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    // Daha toleranslı ayarlar (Donmayı engeller)
                    manifestLoadingTimeOut: 20000,
                    levelLoadingTimeOut: 20000,
                    fragLoadingTimeOut: 20000,
                });
                activePlayers[username] = hls;
                hls.loadSource(src);
                hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    video.muted = true;
                    video.play().catch(() => { });
                });
                // Hata Yönetimi: Dosya yoksa veya ağ hatasıysa tekrar dene
                hls.on(Hls.Events.ERROR, (e, d) => {
                    if (d.fatal) {
                        if (d.type === Hls.ErrorTypes.NETWORK_ERROR) {
                            setTimeout(() => hls.startLoad(), 2000);
                        } else {
                            hls.destroy();
                        }
                    }
                });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = src;
                video.addEventListener('loadedmetadata', () => { video.muted = true; video.play().catch(() => { }); });
            }

            // Kapanış Sinyali
            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${username}`);
            ws.onmessage = (e) => {
                const d = JSON.parse(e.data);
                if (d.type === 'stream_ended') {
                    document.getElementById(`end-screen-${username}`).style.display = 'flex';
                    stopStream(username, video);
                }
            };
            video.dataset.ws = ws;
        }

        function stopStream(username, video) {
            if (activePlayers[username]) {
                activePlayers[username].destroy();
                delete activePlayers[username];
            }
            video.pause();
            video.src = "";
            if (video.dataset.ws) {
                video.dataset.ws.close();
                delete video.dataset.ws;
            }
        }
    }
});