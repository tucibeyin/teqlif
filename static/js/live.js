document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    // 🔥 LOG FONKSİYONU 🔥
    function remoteLog(msg) {
        // Konsola da yaz
        console.log(msg);
        // Sunucuya gönder
        fetch('/log/client', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: `[${MODE.toUpperCase()}] ${msg}` })
        }).catch(() => { });
    }

    remoteLog(`🟢 Sayfa Yüklendi. Platform: ${navigator.platform}, UserAgent: ${navigator.userAgent}`);

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
                    video: { facingMode: 'user', width: { ideal: 540 }, height: { ideal: 960 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera açıldı (540p).");
            } catch (e) {
                remoteLog("❌ KAMERA HATASI: " + e.message);
                alert("Kamera hatası!");
            }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            remoteLog("🚀 Yayın başlatma isteği gönderiliyor...");

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { remoteLog("❌ SUNUCU BAŞLATMA HATASI: " + res.status); return; }

                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                remoteLog("🔗 Socket bağlanıyor...");
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                broadcastWs.onopen = () => {
                    remoteLog("✅ Socket Bağlandı. Veri akışı başlıyor...");
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2000000 };
                        remoteLog("ℹ️ Codec: H.264 kullanılıyor.");
                    } else {
                        remoteLog("ℹ️ Codec: VP8 kullanılıyor.");
                    }

                    try {
                        rec = new MediaRecorder(stream, options);
                    } catch (e) {
                        remoteLog("❌ RECORDER HATASI: " + e.message);
                        rec = new MediaRecorder(stream);
                    }

                    let packetCount = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            broadcastWs.send(e.data);
                            packetCount++;
                            if (packetCount % 20 === 0) remoteLog(`📤 Veri gönderiliyor... (Paket #${packetCount}, Boyut: ${e.data.size})`);
                        }
                    };
                    rec.start(500);

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();

                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 30000);
                };

                broadcastWs.onclose = (e) => {
                    remoteLog(`❌ Socket kapandı! Kod: ${e.code}, Neden: ${e.reason}`);
                    if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/';
                };
            });
        });

        window.stopBroadcast = () => { remoteLog("🛑 Yayın durduruluyor..."); if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`;

        remoteLog(`👀 İzleyici modu aktif. Hedef: ${u}`);

        if (v) {
            // HLS.js Kontrolü
            if (Hls.isSupported()) {
                remoteLog("ℹ️ HLS.js destekleniyor. Başlatılıyor...");
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    remoteLog("✅ HLS Manifest Okundu. Oynatılıyor...");
                    v.muted = true; v.play().catch(e => remoteLog("⚠️ Otoplay hatası: " + e.message));
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });

                hls.on(Hls.Events.ERROR, (event, data) => {
                    remoteLog(`❌ HLS HATASI: ${data.type} - ${data.details}`);
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                remoteLog("⚠️ Ağ hatası, tekrar deneniyor...");
                                hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                remoteLog("⚠️ Medya hatası, kurtarılıyor...");
                                hls.recoverMediaError();
                                break;
                            default:
                                hls.destroy();
                                break;
                        }
                    }
                });
            }
            // iOS Native Kontrolü
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                remoteLog("ℹ️ iOS Native Player kullanılıyor.");
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    remoteLog("✅ iOS Metadata yüklendi.");
                    v.muted = true; v.play().catch(e => remoteLog("⚠️ iOS Otoplay hatası: " + e.message));
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });
                v.addEventListener('error', (e) => {
                    remoteLog(`❌ VİDEO HATASI: ${v.error ? v.error.message : 'Bilinmiyor'} Code: ${v.error ? v.error.code : '?'}`);
                });
            } else {
                remoteLog("❌ HİÇBİR OYNATICI DESTEKLENMİYOR!");
            }
        }
    }
});