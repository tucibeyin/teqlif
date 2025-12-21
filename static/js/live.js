document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) {
        // Hata ayıklama için konsola ve sunucuya log bas
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
                // 9:16 Formatı (720p Dikey)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: {
                        facingMode: 'user',
                        width: { ideal: 720 }, height: { ideal: 1280 },
                        aspectRatio: { ideal: 0.5625 }
                    }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera Bağlandı (Direct Stream)");
            } catch (e) { alert("Kamera Hatası: " + e); remoteLog("❌ Kamera Hatası: " + e); }
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
                    // 🔥 DÜZELTME BURADA: CANVAS YERİNE DİREKT KAMERA 🔥
                    const cameraStream = videoElement.srcObject; // Direkt kamera akışı

                    // Codec Seçimi (PC için H.264, Android için VP8)
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2000000 };
                    }

                    try {
                        rec = new MediaRecorder(cameraStream, options);
                    } catch (e) {
                        remoteLog("❌ Codec Hatası, Varsayılan deneniyor: " + e);
                        rec = new MediaRecorder(cameraStream);
                    }

                    let pktCount = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // RAM Koruması (Buffer şişerse atla)
                            if (broadcastWs.bufferedAmount > 500 * 1024) return;

                            broadcastWs.send(e.data);

                            pktCount++;
                            if (pktCount % 20 === 0) remoteLog(`📤 Veri Gönderiliyor: Pkt #${pktCount}`);
                        } else {
                            remoteLog("⚠️ Boş Veri Paketi (Ignored)");
                        }
                    };

                    // Veri akışını başlat (500ms aralıklarla)
                    rec.start(500);
                    remoteLog(`ℹ️ Kayıt Başladı. Codec: ${rec.mimeType}`);

                    // Thumbnail için Canvas'ı manuel güncelle (Sadece 10 saniyede bir)
                    // Yayın akışını etkilemez, sadece resim çeker.
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            // Videoyu canvas'a anlık çiz
                            ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                            // Resmi gönder
                            fetch('/broadcast/thumbnail', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) })
                            });
                        }
                    }, 10000);
                };

                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/'; };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop();
            if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' });
            location.href = '/';
        };
    }

    // --- İZLEYİCİ (AKILLI BEKÇİ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`;
        const playBtn = document.getElementById(`play-overlay-${u}`);

        remoteLog(`👀 İzleyici Modu: ${u}`);

        // Dosya var mı diye sürekli kontrol et
        function checkFile() {
            fetch(src, { method: 'HEAD' })
                .then(res => {
                    if (res.ok) {
                        remoteLog("✅ Yayın dosyası yakalandı! Oynatıcı başlatılıyor...");
                        initPlayer();
                    } else {
                        remoteLog("⏳ Yayın dosyası bekleniyor...");
                        setTimeout(checkFile, 1500); // 1.5 saniye sonra tekrar bak
                    }
                })
                .catch(() => setTimeout(checkFile, 1500));
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    manifestLoadingTimeOut: 20000,
                    manifestLoadingMaxRetry: 100, // Pes etme
                });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true;
                    v.play().then(() => {
                        if (playBtn) playBtn.style.display = 'none';
                    }).catch(e => {
                        // Otoplay engellenirse butonu göster
                        if (playBtn) {
                            playBtn.style.display = 'flex';
                            playBtn.onclick = () => { v.muted = false; v.play(); playBtn.style.display = 'none'; };
                        }
                    });
                });

                hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR: hls.startLoad(); break;
                            case Hls.ErrorTypes.MEDIA_ERROR: hls.recoverMediaError(); break;
                            default: hls.destroy(); break;
                        }
                    }
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.muted = true; v.play().catch(() => { });
                    if (playBtn) playBtn.style.display = 'none';
                });
                v.addEventListener('error', () => {
                    setTimeout(() => { v.src = src; v.load(); }, 2000);
                });
            }
        }

        checkFile(); // Kontrolü başlat
    }
});