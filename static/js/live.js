document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    window.activeHlsInstances = {};
    let rec = null;
    let broadcastWs = null;
    let localStream = null;

    // --- 1. SOHBET & UI (Mevcut kodların aynısı) ---
    // (Burayı kısaltıyorum, önceki çalışan kodlarındaki chat/ui kısımları aynen kalabilir)
    // Sadece YAYINCI ve İZLEYİCİ kısımlarını değiştirdim.

    window.openModMenu = function (u) { document.getElementById('modMenu').style.display = 'flex'; document.getElementById('mod-target-name').innerText = u; };
    window.closeModMenu = function () { document.getElementById('modMenu').style.display = 'none'; };
    // ... Diğer UI fonksiyonları ...

    // --- 2. YAYINCI (GÜVENLİ VE SABİT) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        const ctx = canvas.getContext('2d', { alpha: false });

        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }
                });
                localStream = stream; videoElement.srcObject = stream;

                function draw() {
                    if (videoElement.readyState === 4) {
                        const vRatio = videoElement.videoWidth / videoElement.videoHeight;
                        const cRatio = canvas.width / canvas.height;
                        let dw, dh, sx, sy;
                        if (vRatio > cRatio) { dh = canvas.height; dw = dh * vRatio; sx = (canvas.width - dw) / 2; sy = 0; }
                        else { dw = canvas.width; dh = dw / vRatio; sx = 0; sy = (canvas.height - dh) / 2; }
                        ctx.drawImage(videoElement, sx, sy, dw, dh);
                    }
                    requestAnimationFrame(draw);
                }
                draw();
            } catch (e) { alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const formData = new FormData();
            formData.append('title', document.getElementById('streamTitle').value || 'Canlı');
            formData.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: formData }).then(res => res.json()).then(data => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(30);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    // WebM/VP8 (En Uyumlu)
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm', videoBitsPerSecond: 1500000 };

                    try { rec = new MediaRecorder(stream, options); }
                    catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data);
                    };

                    rec.start(1000); // 1000ms

                    setInterval(() => {
                        fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.5) }) });
                    }, 60000);
                };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (ONARILMIŞ MOD) ---
    else if (CONFIG.mode === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            const src = `/static/hls/${u}/master.m3u8`;

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,

                    // 🔥 GEVŞETİLMİŞ AYARLAR (Donmayı Önler) 🔥
                    backBufferLength: 90,
                    maxBufferLength: 30, // Daha fazla veri tut
                    liveSyncDurationCount: 4, // 4 parça geriden gel (Daha güvenli)
                    liveMaxLatencyDurationCount: 10,

                    // Hata toleransı
                    manifestLoadingTimeOut: 20000,
                    manifestLoadingMaxRetry: 10,
                    levelLoadingTimeOut: 20000,
                    levelLoadingMaxRetry: 10,
                    fragLoadingTimeOut: 20000,
                    fragLoadingMaxRetry: 10,
                });

                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.play().catch(() => {
                        console.log("Otomatik oynatma engellendi, sessize alınıyor...");
                        v.muted = true;
                        v.play();
                    });
                });

                hls.on(Hls.Events.ERROR, function (event, data) {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                console.log("Ağ hatası, yeniden deneniyor...");
                                hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                console.log("Medya hatası, kurtarılıyor...");
                                hls.recoverMediaError();
                                break;
                            default:
                                hls.destroy();
                                break;
                        }
                    }
                });

            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.play().catch(() => { v.muted = true; v.play(); });
                });
            }
            // window.connectChat(u); // Chat bağlantısı (Eğer UI kodlarını sildiysen burayı açma)
        }
    }

    // --- UI Fonksiyonları (Eksik kalmasın diye minimal ek) ---
    window.sendMsg = function (t) {/*...*/ }
    window.openModMenu = function (u) {/*...*/ }
    window.closeModMenu = function () {/*...*/ }
    window.restrictUser = function (a, d) {/*...*/ }
    window.toggleFollow = function (u) {/*...*/ }
    window.sendBid = function (t, a) {/*...*/ }
    window.sendManualBid = function (t) {/*...*/ }
    window.unmuteVideo = function (u) { const el = document.getElementById(`video-${u}`); if (el) { el.muted = false; } }
});