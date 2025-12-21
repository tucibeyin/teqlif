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
                // 9:16 (720p)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 }, aspectRatio: { ideal: 0.5625 } }
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
                if (!res.ok) { alert("Sunucu Hatası"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };
                    // iOS için H.264 (Destekliyorsa)
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    }

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 500 * 1024) return; // RAM Koruması
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000); // 1 saniyelik paketler (Denge)
                    remoteLog("🚀 Yayın Başladı");

                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 30000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ (AKILLI BEKÇİ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`;
        const playBtn = document.getElementById(`play-overlay-${u}`);

        remoteLog(`👀 Bekçi Modu Başladı: ${u}`);

        // 1. DOSYAYI BEKLEME FONKSİYONU
        function waitForStream() {
            fetch(src, { method: 'HEAD' })
                .then(res => {
                    if (res.ok) {
                        remoteLog("✅ Yayın dosyası bulundu! Başlatılıyor...");
                        initPlayer(); // Dosya varsa player'ı başlat
                    } else {
                        remoteLog("⏳ Yayın hazırlanıyor...");
                        setTimeout(waitForStream, 1500); // 1.5 saniye sonra tekrar dene
                    }
                })
                .catch(() => setTimeout(waitForStream, 1500));
        }

        // 2. PLAYER BAŞLATMA
        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    // Otomatik başlatmayı dene
                    v.muted = true;
                    v.play().then(() => {
                        if (playBtn) playBtn.style.display = 'none';
                    }).catch(() => {
                        // Otoplay engellendiyse butonu göster, tıklayınca aç
                        if (playBtn) {
                            playBtn.style.display = 'flex';
                            playBtn.onclick = () => {
                                v.muted = false;
                                v.play();
                                playBtn.style.display = 'none';
                            };
                        }
                    });
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.muted = true;
                    v.play().then(() => {
                        if (playBtn) playBtn.style.display = 'none';
                    }).catch(() => {
                        if (playBtn) {
                            playBtn.style.display = 'flex';
                            playBtn.onclick = () => {
                                v.muted = false;
                                v.play();
                                playBtn.style.display = 'none';
                            };
                        }
                    });
                });
            }
        }

        // Başlat
        waitForStream();
    }
});