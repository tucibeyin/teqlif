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
                // DOĞAL SENSÖR MODU
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user' }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera Hazır (Native)");
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
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { videoBitsPerSecond: 2500000 };

                    try { rec = new MediaRecorder(cameraStream, options); } catch (e) { rec = new MediaRecorder(cameraStream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 500 * 1024) return;
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);
                    remoteLog(`🚀 Yayın Başladı: ${rec.mimeType}`);

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

    // --- İZLEYİCİ (GEVŞEK & STABIL MOD) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`;
        const endScreen = document.getElementById(`end-screen-${u}`);

        remoteLog(`👀 İzleyici: ${u} (Relaxed)`);

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
                // 🔥 GEVŞEK AYARLAR (Donmayı Engeller) 🔥
                const hls = new Hls({
                    enableWorker: true,
                    // Canlıdan 3 parça (3x2 = 6sn) geride kal
                    liveSyncDurationCount: 3,
                    // 10 parçaya kadar (20sn) gecikmeye izin ver (Seek yapma)
                    liveMaxLatencyDurationCount: 10,
                    // Pes etme, bekle
                    manifestLoadingTimeOut: 20000,
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

            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native (Apple işini bilir)
                v.src = src;
                v.addEventListener('loadedmetadata', () => { v.muted = true; v.play().catch(() => { }); });
                v.addEventListener('error', () => setTimeout(() => { v.src = src; v.load(); }, 2000));
            }
        }

        checkFile();
    }
});