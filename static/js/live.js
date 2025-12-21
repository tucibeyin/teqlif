document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) {
        console.log(msg);
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: `[${MODE}] ${msg}` })
        }).catch(() => { });
    }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 }, aspectRatio: { ideal: 0.5625 } }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera Hazır");
            } catch (e) { alert("Kamera Hatası: " + e); remoteLog("❌ Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Live');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { alert("Sunucu Hatası"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };
                    // PC Chrome için H264 (Daha iyi)
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2000000 };
                    }

                    try {
                        rec = new MediaRecorder(stream, options);
                    } catch (e) {
                        remoteLog("❌ Codec Hatası, Varsayılan deneniyor: " + e);
                        rec = new MediaRecorder(stream);
                    }

                    let pkt = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            broadcastWs.send(e.data);
                            pkt++;
                            if (pkt % 20 === 0) remoteLog(`📤 Veri Gönderiliyor: Paket #${pkt} (${e.data.size} byte)`);
                        } else {
                            remoteLog("⚠️ Boş veri paketi üretildi!");
                        }
                    };
                    // Recorder Start
                    rec.start(500); // 500ms
                    remoteLog(`ℹ️ Recorder Başladı. Codec: ${rec.mimeType}`);

                    // Ayna Modu (Sadece gösterim için, yayına etki etmez)
                    // CSS ile hallediliyor.

                    // Thumbnail
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height); // Anlık çiz
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                        }
                    }, 10000); // 10 saniyede bir güncelle
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
        const playBtn = document.getElementById(`play-overlay-${u}`);

        remoteLog(`👀 İzleyici: ${u}`);

        function checkFile() {
            fetch(src, { method: 'HEAD' }).then(r => {
                if (r.ok) {
                    remoteLog("✅ Yayın dosyası bulundu!");
                    initPlayer();
                } else {
                    remoteLog("⏳ Dosya bekleniyor...");
                    setTimeout(checkFile, 1500);
                }
            });
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls();
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().then(() => { if (playBtn) playBtn.style.display = 'none'; }).catch(() => { });
                });
                hls.on(Hls.Events.ERROR, (e, d) => {
                    if (d.fatal) {
                        switch (d.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR: hls.startLoad(); break;
                            case Hls.ErrorTypes.MEDIA_ERROR: hls.recoverMediaError(); break;
                            default: hls.destroy(); break;
                        }
                    }
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src;
                v.addEventListener('loadedmetadata', () => { v.muted = true; v.play(); });
            }
        }

        checkFile(); // Başla
    }
});