document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;

    function remoteLog(msg) {
        if (msg.includes("✅") || msg.includes("❌") || msg.includes("🚀") || msg.includes("👀")) {
            fetch('/log/client', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ msg: `[${MODE}] ${msg}` })
            }).catch(() => { });
        }
    }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // DOĞAL SENSÖR MODU (EN GENİŞ AÇI)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user' }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera Hazır (Geniş Açı)");
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı Yayın');
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
                            if (broadcastWs.bufferedAmount > 500 * 1024) return;
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);
                    remoteLog("🚀 Yayın Başladı");

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
                    if (!isIntentionalStop) { if (rec) rec.stop(); alert("Kesildi!"); location.href = '/'; }
                };
            });
        });

        window.stopBroadcast = () => {
            isIntentionalStop = true; remoteLog("🛑 Durduruldu.");
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/');
        };
    }

    // --- İZLEYİCİ (SENKRONİZE MOD) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/master.m3u8`;
        const endScreen = document.getElementById(`end-screen-${u}`);

        remoteLog(`👀 İzleyici: ${u} (Sync Mode)`);

        // WebSocket (Kapanış Takibi)
        const chatWs = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${u}`);
        chatWs.onmessage = (e) => {
            const data = JSON.parse(e.data);
            if (data.type === 'stream_ended') {
                if (v) v.pause();
                if (endScreen) endScreen.style.display = 'flex';
                if (window.hlsInstance) window.hlsInstance.destroy();
            }
        };

        function checkFile() {
            fetch(src, { method: 'HEAD' }).then(r => {
                if (r.ok) { remoteLog("✅ Dosya Tamam"); initPlayer(); }
                else { setTimeout(checkFile, 1500); }
            }).catch(() => setTimeout(checkFile, 1500));
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                // 🔥 SENKRONİZASYON AYARLARI 🔥
                // Bu ayarlar herkesin aynı kareye kilitlenmesini sağlar.
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,

                    // Canlı yayının ucundan kaç segment geride durayım? (2 x 2sn = 4sn gecikme hedefi)
                    liveSyncDurationCount: 2,

                    // Eğer 3 segmentten (6 saniyeden) fazla geriye düşersem...
                    liveMaxLatencyDurationCount: 3,

                    // ... Videoyu 1.2x hızlandırıp diğerlerine yetişeyim.
                    maxLiveSyncPlaybackRate: 1.2,

                    // Kalite değişimi için buffer boyutu
                    maxBufferLength: 30
                });

                window.hlsInstance = hls;
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true;
                    v.play().catch(e => console.log("Otoplay engellendi:", e));
                });

                hls.on(Hls.Events.ERROR, (e, d) => {
                    if (d.fatal && d.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad();
                });

                // Ekstra Güvenlik: Eğer 10 saniye geride kalırsa, direkt ileri atla.
                setInterval(() => {
                    if (v && !v.paused && hls.latency > 10) {
                        console.log("⚠️ Çok geride kaldı, senkronize ediliyor...");
                        v.currentTime = v.duration - 2; // Canlı uca 2sn kala zıpla
                    }
                }, 5000);

            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native (Apple kendi senkronizasyonunu yapar)
                v.src = src;
                v.addEventListener('loadedmetadata', () => { v.muted = true; v.play().catch(() => { }); });
            }
        }

        checkFile();
    }
});