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

    // --- 2. YAYINCI (AYNI KALIYOR) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let wakeLock = null;

        async function requestWakeLock() { try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }

        async function initStream() {
            try {
                // Mobilde dikey yayın için height > width istenir ama PC desteği için 480p güvenlidir
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA: Açıldı");
            } catch (e) { remoteLog("❌ KAMERA HATA: " + e, 'ERROR'); alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', 'Live'); fd.append('category', 'Genel');
            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    remoteLog("✅ WS BAĞLANDI. Kayıt başlıyor...");
                    const stream = canvas.captureStream(24);
                    if (videoElement.srcObject.getAudioTracks().length > 0) stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === WebSocket.OPEN) broadcastWs.send(e.data);
                    };
                    rec.start(1000);
                    requestWakeLock();

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();

                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 60000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın bitti."); window.location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/'; };
    }

    // --- 3. İZLEYİCİ (LATENCY KILLER EKLENDİ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);

        if (v) {
            remoteLog(`👀 İZLEYİCİ: Hazır -> ${u}`);
            v.src = `/stream/${u}`;
            v.type = "video/webm";

            // --- 1. LATENCY KILLER (GECİKME YOK EDİCİ) ---
            setInterval(() => {
                if (v.buffered.length > 0) {
                    const end = v.buffered.end(v.buffered.length - 1);
                    const latency = end - v.currentTime;

                    // Eğer gecikme 2 saniyeden fazlaysa, canlıya atla
                    if (latency > 2) {
                        console.log(`⏩ Gecikme (${latency.toFixed(1)}s) düzeltiliyor...`);
                        v.currentTime = end - 0.1; // Sonun 0.1sn gerisine atla
                    }
                }
            }, 2000); // 2 saniyede bir kontrol et

            // --- 2. OYNAT BUTONU ---
            const overlay = document.createElement("div");
            overlay.style.cssText = "position:absolute; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.4); display:flex; justify-content:center; align-items:center; z-index:9999; cursor:pointer;";
            overlay.innerHTML = `<div class="big-play-btn">▶️ CANLI YAYINI İZLE</div>`;
            v.parentElement.appendChild(overlay);

            overlay.onclick = () => {
                v.muted = false;
                v.play().then(() => {
                    overlay.style.display = 'none';
                    remoteLog("✅ Oynatma Başladı (Sesli)");
                }).catch(() => {
                    v.muted = true;
                    v.play().then(() => {
                        overlay.style.display = 'none';
                        remoteLog("✅ Oynatma Başladı (Sessiz)");
                    });
                });
            };

            // Otomatik Dene
            v.muted = true;
            v.play().then(() => overlay.style.display = 'none').catch(() => { });

            v.onerror = () => {
                setTimeout(() => {
                    v.src = `/stream/${u}?t=${Date.now()}`;
                    v.load(); v.play().catch(() => { });
                }, 2000);
            };
        }
    }
});