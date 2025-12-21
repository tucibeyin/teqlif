document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) { console.log(msg); }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // 🔥 KRİTİK AYAR: ASPECT RATIO 9:16 🔥
                // Bu ayar kameranın "Zoom" yapmasını engeller, dikey görüntü alır.
                const constraints = {
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: {
                        facingMode: 'user',
                        // 9/16 = 0.5625 (Tam telefon ekranı oranı)
                        aspectRatio: { ideal: 0.5625 },
                        width: { ideal: 720 },  // 720p Kalite
                        height: { ideal: 1280 },
                        frameRate: { ideal: 24 }
                    }
                };

                const stream = await navigator.mediaDevices.getUserMedia(constraints);
                videoElement.srcObject = stream;

                // Yayıncının kendini "Ayna" gibi görmesi için (Video zaten CSS ile döndürüldü)
                // Ama stream'in ham halini bozmamalıyız.
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { alert("Hata!"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // Android için VP8 (Güvenli), iOS izlesin diye sunucu çevirecek
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };

                    try {
                        rec = new MediaRecorder(stream, options);
                    } catch (e) {
                        rec = new MediaRecorder(stream);
                    }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data);
                    };
                    rec.start(1000);

                    // Canvas Döngüsü (Görüntüyü düzeltir)
                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) {
                            // Videoyu canvas'a çizerken aspect ratio koru
                            const vWidth = videoElement.videoWidth;
                            const vHeight = videoElement.videoHeight;

                            // Merkeze oturt (Center Crop)
                            const sHeight = vHeight;
                            const sWidth = (vHeight * 9) / 16;
                            const sX = (vWidth - sWidth) / 2;

                            // Eğer kamera 4:3 veriyorsa, kenarları kırpıp 9:16 yapıyoruz (Zoom değil, Crop)
                            ctx.drawImage(videoElement, sX, 0, sWidth, sHeight, 0, 0, canvas.width, canvas.height);
                        }
                        requestAnimationFrame(draw);
                    }
                    draw();

                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 30000);
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
        const src = `/static/hls/${u}/index.m3u8`;

        window.forcePlay = function (target) {
            const vid = document.getElementById(`video-${target}`);
            const btn = document.getElementById(`play-overlay-${target}`);
            if (btn) btn.style.display = 'none';
            if (vid) { vid.muted = false; vid.play().catch(() => { vid.muted = true; vid.play() }); }
        };

        if (v) {
            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().then(() => {
                        const ov = document.getElementById(`play-overlay-${u}`);
                        if (ov) ov.style.display = 'none';
                    }).catch(() => { });
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.muted = true; v.play().catch(() => { });
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });
            }
        }
    }
});