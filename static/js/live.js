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
                // 9:16 Aspect Ratio (Selfie Modu)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: {
                        facingMode: 'user',
                        width: { ideal: 720 }, height: { ideal: 1280 }, // 720p HD
                        frameRate: { ideal: 24 },
                        aspectRatio: { ideal: 0.5625 } // 9:16
                    }
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

                    // Codec: VP8 (Android dostu), Bitrate: 1.5Mbps (Stabil)
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1500000 };

                    // Fallback
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        options = { videoBitsPerSecond: 1500000 };
                    }

                    rec = new MediaRecorder(stream, options);

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // 🔥 KRİTİK RAM KORUMASI (BACKPRESSURE) 🔥
                            // Eğer gönderilmeyi bekleyen veri 250KB'dan fazlaysa,
                            // yeni paketi gönderme. Bu, tarayıcının çökmesini engeller.
                            if (broadcastWs.bufferedAmount > 250 * 1024) {
                                console.warn("⚠️ Ağ yavaş, paket atlandı (RAM Koruması)");
                                return;
                            }
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000); // 1 saniyelik paketler

                    // Ayna Modu Çizimi
                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) {
                            const vW = videoElement.videoWidth;
                            const vH = videoElement.videoHeight;
                            // Aspect Ratio koruyarak çiz
                            const sH = vH;
                            const sW = (vH * 9) / 16;
                            const sX = (vW - sW) / 2;

                            ctx.drawImage(videoElement, sX, 0, sWidth, sHeight, 0, 0, canvas.width, canvas.height);
                        }
                        requestAnimationFrame(draw);
                    }
                    // draw(); // Canvas işlemini kapattım, direkt stream'i alalım (Performans için)
                    // Not: Aynalama CSS ile yapıldığı için canvas'a gerek yok, direkt stream gitsin.
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
                const hls = new Hls({ enableWorker: true });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().then(() => {
                        const ov = document.getElementById(`play-overlay-${u}`);
                        if (ov) ov.style.display = 'none';
                    }).catch(() => { });
                });
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