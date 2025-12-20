document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg, level = 'INFO') {
        // Konsolu kirletmemek için remote logu kapattım, gerekirse açabilirsin
        // console.log(`[${level}] ${msg}`);
    }

    // Global Oynat Fonksiyonu
    window.forcePlay = function (username) {
        const overlay = document.getElementById(`play-overlay-${username}`);
        const v = document.getElementById(`video-${username}`);
        if (overlay) overlay.style.display = 'none';
        if (v) {
            v.src = `/stream/${username}`;
            v.type = "video/webm";
            v.muted = false;
            v.play().catch(() => { v.muted = true; v.play(); });
        }
    };

    // --- YAYINCI ---
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
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value);
            fd.append('category', document.getElementById('streamCategory').value);

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(1000); // 1 sn gecikme payı

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

    // --- İZLEYİCİ (GECİKME ÖNLEYİCİ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            // Otomatik Başlat
            v.src = `/stream/${u}`;
            v.muted = true;
            v.play().then(() => {
                const overlay = document.getElementById(`play-overlay-${u}`);
                if (overlay) overlay.style.display = 'none';
            }).catch(() => { });

            // 🔥 LATENCY KILLER (GECİKME YOK EDİCİ) 🔥
            // İzleyicinin geride kalmasını engeller.
            setInterval(() => {
                if (v.buffered.length > 0) {
                    const end = v.buffered.end(v.buffered.length - 1);
                    // Eğer canlı ucun 1.5 saniye gerisindeysek...
                    if (end - v.currentTime > 1.5) {
                        console.log("⏩ Senkronizasyon: İleri sarılıyor...");
                        v.currentTime = end - 0.1; // En uca atla
                    }
                }
            }, 2000);

            // Kopma Yönetimi
            v.onerror = () => { setTimeout(() => { v.src = `/stream/${u}?t=${Date.now()}`; v.load(); v.play().catch(() => { }); }, 1500); };
        }
    }
});