document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) { console.log(msg); }

    // --- YAYINCI (GÜVENLİ MOD) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // 540p (qHD) - Altın Oran. Hem net hem hafif.
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 540 }, height: { ideal: 960 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            fetch('/broadcast/start', { method: 'POST', body: new FormData() }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // 🔥 AKILLI CODEC SEÇİCİ 🔥
                    // Telefonu yormadan en iyi formatı seçer.
                    // 1.5 Mbps (1500000) = Donma yapmaz, kalitesi iyidir.
                    const bitrate = 1500000;
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: bitrate };

                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: bitrate };
                    }

                    try {
                        rec = new MediaRecorder(stream, options);
                    } catch (e) {
                        console.error("Codec hatası, varsayılan deneniyor...");
                        rec = new MediaRecorder(stream); // En güvenli fallback
                    }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data);
                    };
                    rec.start(1000); // 1 saniyelik paketler

                    // Canvas Döngüsü
                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();

                    // Thumbnail
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                    }, 30000); // 30 sn'de bir (Performans için)
                };

                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ (HLS PLAYER) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`; // Standart isim

        if (v) {
            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().catch(() => { });
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });
                // Hata Yönetimi
                hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR: hls.startLoad(); break;
                            case Hls.ErrorTypes.MEDIA_ERROR: hls.recoverMediaError(); break;
                            default: hls.destroy(); break;
                        }
                    }
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