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

    // SAYFA YÜKLENİNCE İLK LOG
    remoteLog(`🟢 JS YÜKLENDİ (V: ${Math.random().toFixed(4)}) - Mod: ${MODE}`);

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: { facingMode: 'user', width: 640, height: 480, frameRate: 24 } });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA: Hazır");
            } catch (e) { remoteLog("❌ KAMERA: " + e, 'ERROR'); alert("Kamera Hatası!"); }
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
                    remoteLog("✅ WS BAĞLI. Veri akışı başlıyor...");
                    const stream = canvas.captureStream(24);
                    // Ses
                    if (videoElement.srcObject && videoElement.srcObject.getAudioTracks().length > 0)
                        stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    rec = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 });

                    let pkt = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === WebSocket.OPEN) {
                            broadcastWs.send(e.data);
                            pkt++;
                            if (pkt % 20 === 0) remoteLog(`📤 Pkt #${pkt} (${e.data.size}b)`);
                        }
                    };
                    rec.start(1000);

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();
                };

                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın bitti."); window.location.href = '/'; };
            });
        });

        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/'; };
    }

    // --- İZLEYİCİ (LOGIC HTML İÇİNDE "forcePlay" İLE TETİKLENİYOR) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        remoteLog(`👀 İZLEYİCİ: Hazır (${CONFIG.broadcaster})`);
        // Chat bağlantısı
        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${CONFIG.broadcaster}`);
        ws.onopen = () => remoteLog("💬 Chat Bağlandı");

        // Video elementini bul ve logla
        const v = document.getElementById(`video-${CONFIG.broadcaster}`);
        if (v) {
            v.onwaiting = () => remoteLog("⏳ Video Tamponluyor...");
            v.onplaying = () => remoteLog("▶️ Video Oynuyor!");
            v.onerror = (e) => remoteLog("❌ Video Hatası: " + (v.error ? v.error.message : "Bilinmeyen"));
        } else {
            remoteLog("⚠️ Video elementi bulunamadı!");
        }
    }
});