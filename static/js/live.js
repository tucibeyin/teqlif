document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false; // Kasıtlı durdurma kontrolü

    function remoteLog(msg) {
        // Konsol temizliği için gereksiz logları sunucuya atma
        console.log(msg);
        // Sadece önemli olayları sunucuya bildir
        if (msg.includes("✅") || msg.includes("❌") || msg.includes("🚀") || msg.includes("👀")) {
            fetch('/log/client', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ msg: `[${MODE}] ${msg}` })
            }).catch(() => { });
        }
    }

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                // 9:16 (720p)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 }, aspectRatio: { ideal: 0.5625 } }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera Hazır (9:16 Direct)");
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı Yayın');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { alert("Sunucu Hatası"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                broadcastWs.onopen = () => {
                    const cameraStream = videoElement.srcObject;

                    // Codec Seçimi (PC: H264, Android: VP8)
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2000000 };
                    }

                    try { rec = new MediaRecorder(cameraStream, options); }
                    catch (e) { rec = new MediaRecorder(cameraStream); }

                    let pktCount = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 500 * 1024) return; // RAM Koruması
                            broadcastWs.send(e.data);
                            pktCount++;
                            // Log kirliliği yapmasın diye sadece konsola yaz
                            if (pktCount % 50 === 0) console.log(`Veri Pkt: ${pktCount}`);
                        }
                    };
                    rec.start(500);
                    remoteLog("🚀 Yayın Başladı");

                    // Thumbnail (15sn)
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };

                // Kapanış Yönetimi
                broadcastWs.onclose = () => {
                    if (!isIntentionalStop) {
                        if (rec) rec.stop();
                        alert("Yayın Bağlantısı Kesildi!");
                        location.href = '/';
                    }
                };
            });
        });

        // Temiz Durdurma Fonksiyonu
        window.stopBroadcast = () => {
            isIntentionalStop = true; // Kasıtlı durdurma bayrağını çek
            remoteLog("🛑 Yayıncı durdurdu.");

            if (rec && rec.state !== 'inactive') rec.stop();
            if (broadcastWs) broadcastWs.close();

            // Sunucuya bildir ve git
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => {
                location.href = '/';
            });
        };
    }

    // --- İZLEYİCİ (AKILLI BEKÇİ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`;
        const playBtn = document.getElementById(`play-overlay-${u}`);

        remoteLog(`👀 İzleyici: ${u}`);

        function checkFile() {
            fetch(src, { method: 'HEAD' }).then(r => {
                if (r.ok) {
                    remoteLog("✅ Yayın Bulundu!");
                    initPlayer();
                } else {
                    console.log("Dosya bekleniyor...");
                    setTimeout(checkFile, 1000);
                }
            }).catch(() => setTimeout(checkFile, 1000));
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    backBufferLength: 30,
                    // Hata durumunda hemen pes etme
                    manifestLoadingTimeOut: 15000,
                    manifestLoadingMaxRetry: 10,
                });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true;
                    v.play().then(() => {
                        if (playBtn) playBtn.style.display = 'none';
                    }).catch(() => {
                        if (playBtn) {
                            playBtn.style.display = 'flex';
                            playBtn.onclick = () => { v.muted = false; v.play(); playBtn.style.display = 'none'; };
                        }
                    });
                });

                // Hata Yönetimi
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
                // iOS Native
                v.src = src;
                v.addEventListener('loadedmetadata', () => { v.muted = true; v.play().catch(() => { }); });
                v.addEventListener('error', () => setTimeout(() => { v.src = src; v.load(); }, 2000));
            }
        }

        checkFile();
    }
});