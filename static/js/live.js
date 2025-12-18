document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    // 🔥 DEBUG LOG 🔥
    function log(msg) {
        console.log(msg);
        const box = document.getElementById('debug-console');
        if (box) {
            box.innerHTML += `<div>> ${msg}</div>`;
            box.scrollTop = box.scrollHeight;
        }
    }

    window.CURRENT_SOCKET = null;
    window.activeHlsInstances = {};
    let rec = null;
    let broadcastWs = null;
    let localStream = null;

    // --- UI/MODERASYON ---
    window.openModMenu = function (u) {/*...*/ };
    window.closeModMenu = function () {/*...*/ };
    window.restrictUser = function (a, d) {/*...*/ };

    // --- SOHBET ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        window.CURRENT_SOCKET = ws;
        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);
            if (d.type === 'chat') {
                log(`Chat: ${d.user}: ${d.msg}`);
                // Chat UI güncelleme kodu...
            }
        };
    };

    // --- 2. YAYINCI (ANTI-CRASH MODE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                localStream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }
                });
                videoElement.srcObject = localStream;
                log("Kamera Aktif.");

                function draw() {
                    if (videoElement.readyState === 4) {
                        const vRatio = videoElement.videoWidth / videoElement.videoHeight;
                        const cRatio = canvas.width / canvas.height;
                        let dw, dh, sx, sy;
                        if (vRatio > cRatio) { dh = canvas.height; dw = dh * vRatio; sx = (canvas.width - dw) / 2; sy = 0; }
                        else { dw = canvas.width; dh = dw / vRatio; sx = 0; sy = (canvas.height - dh) / 2; }
                        canvas.getContext('2d').drawImage(videoElement, sx, sy, dw, dh);
                    }
                    requestAnimationFrame(draw);
                }
                draw();
            } catch (e) { log("Kamera Hatası: " + e); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            fetch('/broadcast/start', { method: 'POST', body: new FormData(document.querySelector('.setup-box')) }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                window.connectChat('broadcast');

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    log("WS Bağlandı.");
                    const stream = canvas.captureStream(30);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    let opts = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1200000 }; // 1.2 Mbps (Daha güvenli)
                    if (!MediaRecorder.isTypeSupported(opts.mimeType)) opts = { mimeType: 'video/webm' };

                    try { rec = new MediaRecorder(stream, opts); } catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => {
                        // 🔥 CRASH ÖNLEYİCİ: Backpressure Kontrolü 🔥
                        if (broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 1000000) { // 1MB'dan fazla veri kuyrukta ise
                                log("⚠️ Ağ Yavaş! Veri atlanıyor...");
                            } else {
                                broadcastWs.send(e.data);
                            }
                        }
                    };

                    rec.start(1000); // 1000ms Chunk
                    log("Recorder Başladı.");

                    setInterval(() => {
                        fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.5) }) });
                    }, 60000);
                };
                broadcastWs.onclose = () => log("WS Kapandı!");
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (DEBUGGER) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`;
            log("Yayın Aranıyor: " + u);

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    liveSyncDurationCount: 3,
                    maxBufferLength: 20,
                });

                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    log("Manifest Bulundu ✅");
                    v.play().catch(() => { log("Otomatik oynatma engellendi"); v.muted = true; v.play(); });
                });

                hls.on(Hls.Events.ERROR, function (event, data) {
                    log("HLS Hatası: " + data.type);
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                log("Ağ Hatası - Tekrar deneniyor...");
                                hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                log("Medya Hatası - Kurtarılıyor...");
                                hls.recoverMediaError();
                                break;
                            default:
                                log("Kritik Hata!");
                                hls.destroy();
                                break;
                        }
                    }
                });
            }
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                log("Native Player Kullanılıyor.");
                v.src = src;
                v.play();
            }
            window.connectChat(u);
        }
    }
});