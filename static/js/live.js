document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) {
        console.log(msg);
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: `[${MODE}] ${msg}` })
        }).catch(() => { });
    }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // EN GENİŞ AÇI (Native)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', frameRate: { ideal: 24 } }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera Hazır (Geniş Açı)");
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
                    const cameraStream = videoElement.srcObject;

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    }

                    try { rec = new MediaRecorder(cameraStream, options); }
                    catch (e) { rec = new MediaRecorder(cameraStream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 500 * 1024) return;
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);
                    remoteLog("🚀 Yayın Başladı");

                    // Thumbnail
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const canvas = document.getElementById('broadcast-canvas');
                            const ctx = canvas.getContext('2d');
                            const vW = videoElement.videoWidth;
                            const vH = videoElement.videoHeight;

                            // Smart Crop for Thumbnail (9:16)
                            const targetRatio = 9 / 16;
                            const sourceRatio = vW / vH;
                            let sW, sH, sX, sY;

                            if (sourceRatio > targetRatio) {
                                sH = vH; sW = vH * targetRatio; sX = (vW - sW) / 2; sY = 0;
                            } else {
                                sW = vW; sH = vW / targetRatio; sX = 0; sY = (vH - sH) / 2;
                            }

                            ctx.drawImage(videoElement, sX, sY, sW, sH, 0, 0, canvas.width, canvas.height);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        // 🔥 ARTIK MASTER PLAYLIST ÇAĞIRIYORUZ 🔥
        const src = `/static/hls/${u}/master.m3u8`;
        const playBtn = document.getElementById(`play-overlay-${u}`);

        remoteLog(`👀 İzleyici: ${u} (Multi-Quality)`);

        function checkFile() {
            fetch(src, { method: 'HEAD' }).then(r => {
                if (r.ok) {
                    remoteLog("✅ Yayın Bulundu!");
                    initPlayer();
                } else {
                    setTimeout(checkFile, 1500);
                }
            }).catch(() => setTimeout(checkFile, 1500));
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    // Otomatik kalite seçimi aktif
                    capLevelToPlayerSize: true
                });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().then(() => {
                        if (playBtn) playBtn.style.display = 'none';
                    }).catch(() => {
                        if (playBtn) {
                            playBtn.style.display = 'flex';
                            playBtn.onclick = () => { v.muted = false; v.play(); playBtn.style.display = 'none'; };
                        }
                    });
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native (Otomatik olarak master.m3u8 içindeki kaliteleri görür)
                v.src = src;
                v.addEventListener('loadedmetadata', () => { v.muted = true; v.play().catch(() => { }); });
                v.addEventListener('error', () => setTimeout(() => { v.src = src; v.load(); }, 2000));
            }
        }

        checkFile();
    }
});