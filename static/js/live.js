document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) { console.log(msg); }

    // --- YAYINCI (PREMIUM KALİTE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // Kaynak kalitesini artırdık: 720p @ 30fps
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 }, frameRate: 30 }
                });
                videoElement.srcObject = stream;
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value);
            fd.append('category', document.getElementById('streamCategory').value);

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(30);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // 🔥 ULTRA YÜKSEK BITRATE (4 Mbps) 🔥
                    // Sunucuya ne kadar kaliteli veri giderse, çıktı o kadar iyi olur.
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 4000000 };

                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        console.log("H.264 desteklenmiyor, VP8'e düşülüyor (Kalite düşebilir).");
                        options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 4000000 };
                    }

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data);
                    };
                    rec.start(1000); // 1 saniyelik paketler

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();

                    // Thumbnail
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                    }, 60000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ (ADAPTIVE HLS) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/master.m3u8`;

        if (v) {
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    backBufferLength: 90
                });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true;
                    v.play().then(() => {
                        const ov = document.getElementById(`play-overlay-${u}`);
                        if (ov) ov.style.display = 'none';
                    }).catch(() => { });
                });

                // Kalite değişimlerini logla (Merak edersen konsoldan bak)
                hls.on(Hls.Events.LEVEL_SWITCHED, (event, data) => {
                    console.log(`🎚️ Kalite Değişti: Seviye ${data.level}`);
                });

            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native Player
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.muted = true; v.play().catch(() => { });
                });
            }
        }
    }
});