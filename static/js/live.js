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

    // Global Fonksiyon: İzleyici Butonuna Basınca
    window.forcePlay = function (username) {
        remoteLog(`🖱️ İZLEME TETİKLENDİ: ${username}`);
        const overlay = document.getElementById(`play-overlay-${username}`);
        const v = document.getElementById(`video-${username}`);

        if (overlay) overlay.style.display = 'none';

        if (v) {
            v.src = `/stream/${username}`;
            v.type = "video/webm";
            v.muted = false; // Sesli dene
            v.play().then(() => remoteLog("✅ SESLİ OYNATILIYOR"))
                .catch(() => {
                    remoteLog("⚠️ Ses engellendi, sessiz açılıyor");
                    v.muted = true;
                    v.play();
                });
        }
    };

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        // Kamerayı Başlat
        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: { facingMode: 'user', width: 640, height: 480, frameRate: 24 } });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA AÇIK");
            } catch (e) { remoteLog("❌ KAMERA HATASI: " + e); alert("Kamera açılamadı!"); }
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
                    remoteLog("✅ YAYIN BAŞLADI");
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(1000);

                    // Canvas Döngüsü
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
            remoteLog(`👀 İZLEYİCİ GELDİ: ${u}`);
            // Otomatik Başlatmayı Dene (Sessiz)
            v.src = `/stream/${u}`;
            v.muted = true;
            v.play().then(() => {
                const overlay = document.getElementById(`play-overlay-${u}`);
                if (overlay) overlay.style.display = 'none'; // Başarılıysa butonu gizle
                remoteLog("✅ OTOMATİK BAŞLADI");
            }).catch(() => {
                remoteLog("ℹ️ OTO-BAŞLAT ENGELLENDİ (BUTON BEKLENİYOR)");
            });

            // Hata Yönetimi
            v.onerror = () => { setTimeout(() => { v.src = `/stream/${u}?t=${Date.now()}`; v.load(); v.play().catch(() => { }); }, 2000); };
        }
    }
});