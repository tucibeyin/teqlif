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
                // 9:16 ve 24 FPS
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 }, frameRate: 24, aspectRatio: { ideal: 0.5625 } }
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
                if (!res.ok) { alert("Sunucu Hatası!"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // Android = VP8 (Güvenli)
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };
                    // iOS = H.264 (Destekliyorsa)
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2000000 };
                    }

                    rec = new MediaRecorder(stream, options);

                    // 250KB Buffer Kontrolü (RAM Koruması)
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 250 * 1024) return; // Drop frame
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);

                    // Ayna Modu (Sadece görüntü için, stream ham gider)
                    // CSS transform: scaleX(-1) işi hallediyor.

                    setInterval(() => {
                        if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                    }, 30000);
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
                const hls = new Hls({
                    enableWorker: true,
                    // Hata toleransı ayarları
                    manifestLoadingTimeOut: 10000,
                    manifestLoadingMaxRetry: 10, // 10 kere dene (Dosya oluşana kadar)
                    manifestLoadingRetryDelay: 1000,
                });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().catch(() => { });
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });

                hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                console.log("Ağ hatası, tekrar deneniyor...");
                                hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                console.log("Medya hatası, kurtarılıyor...");
                                hls.recoverMediaError();
                                break;
                            default: hls.destroy(); break;
                        }
                    }
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native (Otomatik retry yapmaz, biz zorlarız)
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.muted = true; v.play().catch(() => { });
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });
                // iOS Hata Yönetimi
                v.addEventListener('error', () => {
                    setTimeout(() => {
                        v.src = src; // Yeniden yükle
                        v.load();
                    }, 2000);
                });
            }
        }
    }
});