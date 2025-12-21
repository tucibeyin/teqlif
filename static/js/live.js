document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;

    function remoteLog(msg) {
        console.log(msg);
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
                // 🔥 GENİŞ AÇI AYARI 🔥
                // Çözünürlük (720p) zorlamasını kaldırdık.
                // Sadece Aspect Ratio (9:16) istiyoruz. Telefon en geniş açıyı seçecek.
                const constraints = {
                    audio: {
                        echoCancellation: true,
                        noiseSuppression: true,
                        autoGainControl: true
                    },
                    video: {
                        facingMode: 'user',
                        // ideal: 0.5625 = 9/16 (Tam Dikey)
                        aspectRatio: { ideal: 0.5625 }
                    }
                };

                const stream = await navigator.mediaDevices.getUserMedia(constraints);
                videoElement.srcObject = stream;

                // Gerçekten hangi çözünürlüğü aldığımızı loglayalım
                const track = stream.getVideoTracks()[0];
                const settings = track.getSettings();
                remoteLog(`✅ Kamera Hazır: ${settings.width}x${settings.height} (${(settings.width / settings.height).toFixed(2)})`);

            } catch (e) {
                alert("Kamera Açılamadı: " + e);
                remoteLog("❌ Kamera Hatası: " + e);
            }
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
                    // DİREKT KAMERA AKIŞI (Canvas Yok, Performans Modu)
                    const cameraStream = videoElement.srcObject;

                    // Codec Seçimi (H.264 tercih et, yoksa VP8)
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };
                    }
                    // Fallback
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        options = { videoBitsPerSecond: 2500000 };
                    }

                    try {
                        rec = new MediaRecorder(cameraStream, options);
                    } catch (e) {
                        remoteLog("❌ Recorder Hatası: " + e);
                        rec = new MediaRecorder(cameraStream); // En basit haliyle dene
                    }

                    let pktCount = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // Buffer şişerse (internet yavaşsa) paketi atla
                            if (broadcastWs.bufferedAmount > 500 * 1024) return;

                            broadcastWs.send(e.data);
                            pktCount++;
                            if (pktCount % 50 === 0) console.log(`Pkt: ${pktCount}`);
                        }
                    };

                    // 1 saniyelik paketler (Stabilite için en iyisi)
                    rec.start(1000);
                    remoteLog(`🚀 Yayın Başladı. Codec: ${rec.mimeType}`);

                    // Thumbnail (Her 15 saniyede bir)
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            // Videonun o anki karesini canvas'a çiz
                            // Aspect ratio koruyarak ortala (Center Crop for Thumbnail)
                            const vW = videoElement.videoWidth;
                            const vH = videoElement.videoHeight;
                            const targetRatio = 9 / 16;

                            let sW, sH, sX, sY;

                            if (vW / vH > targetRatio) {
                                // Video daha geniş, yanlardan kırp
                                sH = vH;
                                sW = vH * targetRatio;
                                sX = (vW - sW) / 2;
                                sY = 0;
                            } else {
                                // Video daha uzun, üstten/alttan kırp
                                sW = vW;
                                sH = vW / targetRatio;
                                sX = 0;
                                sY = (vH - sH) / 2;
                            }

                            ctx.drawImage(videoElement, sX, sY, sW, sH, 0, 0, canvas.width, canvas.height);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };

                broadcastWs.onclose = () => {
                    if (!isIntentionalStop) {
                        if (rec) rec.stop();
                        alert("Yayın Bağlantısı Koptu!");
                        location.href = '/';
                    }
                };
            });
        });

        window.stopBroadcast = () => {
            isIntentionalStop = true;
            remoteLog("🛑 Yayıncı durdurdu.");
            if (rec && rec.state !== 'inactive') rec.stop();
            if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/');
        };
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
                    remoteLog("✅ Dosya Bulundu");
                    initPlayer();
                } else {
                    setTimeout(checkFile, 1500);
                }
            }).catch(() => setTimeout(checkFile, 1500));
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    liveSyncDurationCount: 3,
                    liveMaxLatencyDurationCount: 6,
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
                v.addEventListener('loadedmetadata', () => { v.muted = true; v.play().catch(() => { }); });
                v.addEventListener('error', () => setTimeout(() => { v.src = src; v.load(); }, 2000));
            }
        }

        checkFile();
    }
});