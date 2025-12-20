document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg, level = 'INFO') {
        console.log(`[${level}] ${msg}`);
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: msg, level: level })
        }).catch(() => { });
    }

    // Global Oynat Fonksiyonu
    window.forcePlay = function (username) {
        const overlay = document.getElementById(`play-overlay-${username}`);
        const v = document.getElementById(`video-${username}`);
        if (overlay) overlay.style.display = 'none';
        if (v) {
            // iOS Cache Kırmak için timestamp
            v.src = `/stream/${username}?t=${Date.now()}`;
            v.type = "video/webm"; // iOS için teknik olarak mp4 olması gerekebilir ama tarayıcılar bazen bunu yutar
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
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA AÇIK");
            } catch (e) { remoteLog("❌ KAMERA HATASI: " + e); alert("Kamera Hatası!"); }
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
                    if (videoElement.srcObject.getAudioTracks().length > 0)
                        stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // 🔥 KRİTİK: İLK ÖNCE H.264 DENE (iOS DOSTU) 🔥
                    let mimeType = 'video/webm;codecs=vp8'; // Varsayılan (Android/PC)

                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        mimeType = 'video/webm;codecs=h264';
                        remoteLog("✅ Codec: H.264 (iOS Uyumlu)");
                    } else if (MediaRecorder.isTypeSupported('video/x-matroska;codecs=h264')) {
                        mimeType = 'video/x-matroska;codecs=h264';
                        remoteLog("✅ Codec: MKV H.264");
                    } else {
                        remoteLog("⚠️ H.264 Yok, VP8 kullanılıyor (iOS sorun çıkarabilir)");
                    }

                    try {
                        rec = new MediaRecorder(stream, { mimeType: mimeType, videoBitsPerSecond: 1000000 });
                    } catch (e) {
                        remoteLog("Codec hatası, fallback yapılıyor...");
                        rec = new MediaRecorder(stream); // En ilkel moda dön
                    }

                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(1000);

                    // Canvas Loop
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

    // --- İZLEYİCİ ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog(`👀 İZLEYİCİ: ${u}`);

            // Otomatik Başlat
            v.src = `/stream/${u}`;
            v.muted = true;
            v.play().then(() => {
                const overlay = document.getElementById(`play-overlay-${u}`);
                if (overlay) overlay.style.display = 'none';
            }).catch(() => { });

            // Gecikme Kontrolü (1.5s Tolerans)
            setInterval(() => {
                if (v.buffered.length > 0) {
                    const end = v.buffered.end(v.buffered.length - 1);
                    if (end - v.currentTime > 1.5) v.currentTime = end - 0.1;
                }
            }, 2000);

            // Hata Yönetimi
            v.onerror = () => { setTimeout(() => { v.src = `/stream/${u}?t=${Date.now()}`; v.load(); v.play().catch(() => { }); }, 1500); };
        }
    }
});