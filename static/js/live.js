document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) { console.log(msg); }

    // --- YAYINCI (H.264 ZORUNLU) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: { facingMode: 'user', width: 640, height: 480, frameRate: 24 } });
                videoElement.srcObject = stream;
            } catch (e) { alert("Kamera Hatası!"); }
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

                    // 🔥 H.264 ZORUNLU (iOS ve HLS UYUMU İÇİN) 🔥
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 1500000 };

                    // Eğer tarayıcı H.264 desteklemiyorsa bu sistem çalışmaz (FFmpeg copy için H264 şart)
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        alert("Cihazınız H.264 Yayınını Desteklemiyor! Yayın açılamaz.");
                        window.location.href = '/';
                        return;
                    }

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(1000);

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();
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
        const src = `/static/hls/${u}/master.m3u8`;

        if (v) {
            // 1. HLS.js Desteği (PC/Android)
            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play(); }));

                // Hata Yönetimi
                hls.on(Hls.Events.ERROR, function (event, data) {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                console.log("Ağ hatası, toparlanıyor...");
                                hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                console.log("Medya hatası, toparlanıyor...");
                                hls.recoverMediaError();
                                break;
                            default:
                                hls.destroy();
                                break;
                        }
                    }
                });
            }
            // 2. Native HLS Desteği (iOS Safari)
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src;
                v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play(); }));
            }
        }
    }
});