document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    window.activeHlsInstances = {};
    let rec = null;
    let broadcastWs = null;
    let localStream = null;

    // --- UI/MODERASYON (Eski kodlar aynı kalabilir) ---
    window.openModMenu = function (u) { document.getElementById('modMenu').style.display = 'flex'; document.getElementById('mod-target-name').innerText = u; };
    window.closeModMenu = function () { document.getElementById('modMenu').style.display = 'none'; };
    window.restrictUser = function (a, d) {/*...*/ };
    window.updatePriceDisplay = function (a, t, n) {/*...*/ };
    window.toggleAuction = function () {/*...*/ };
    window.openResetModal = function () { document.getElementById('resetModal').style.display = 'flex'; };
    window.closeResetModal = function () { document.getElementById('resetModal').style.display = 'none'; };
    window.confirmReset = function () {/*...*/ };
    window.sendBid = function (t, a) {/*...*/ };
    window.sendManualBid = function (t) {/*...*/ };
    window.sendMsg = function (t) { const i = document.getElementById('chat-input-' + (t == 'broadcast' ? 'broadcast' : t)); if (i && i.value.trim()) { window.CURRENT_SOCKET.send(i.value); i.value = ''; i.focus(); } };
    window.openGiftMenu = function (u) { document.getElementById('giftMenu').style.display = 'block'; };
    window.closeGiftMenu = function () { document.getElementById('giftMenu').style.display = 'none'; };
    window.sendGift = function (t) {/*...*/ };
    window.toggleFollow = function (u) {/*...*/ };
    window.unmuteVideo = function (u) { const v = document.getElementById('video-' + u); if (v) { v.muted = false; } };

    // --- CHAT BAĞLANTISI ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        window.CURRENT_SOCKET = ws;
        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);
            if (d.type === 'chat') {
                const fid = target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`;
                const f = document.getElementById(fid);
                if (f) { const el = document.createElement('div'); el.className = 'msg'; el.innerHTML = `<b>${d.user}:</b> ${d.msg}`; f.appendChild(el); f.scrollTop = f.scrollHeight; }
            }
        };
    };

    // --- 2. YAYINCI (ANDROID SAFE MODE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
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
                        canvas.getContext('2d').drawImage(videoElement, sx, sy, dw, dh);
                    }
                    requestAnimationFrame(draw);
                }
                draw();
            } catch (e) { alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                window.connectChat('broadcast');

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(30);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    // VP8 / 1.5 Mbps
                    let opts = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1500000 };
                    if (!MediaRecorder.isTypeSupported(opts.mimeType)) opts = { mimeType: 'video/webm', videoBitsPerSecond: 1500000 };

                    try { rec = new MediaRecorder(stream, opts); } catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };

                    rec.start(1000); // 1000ms Chunk

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

    // --- 3. İZLEYİCİ (ULTRA TOLERANSLI) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            // 🔥 CACHE ÖNLEYİCİ URL 🔥
            const src = `/static/hls/${u}/master.m3u8?t=${Math.floor(Date.now() / 1000)}`;

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    liveSyncDurationCount: 3,
                    maxBufferLength: 30, // 30sn buffer
                    manifestLoadingTimeOut: 20000,
                    manifestLoadingMaxRetry: 5,
                    levelLoadingTimeOut: 20000,
                    levelLoadingMaxRetry: 5,
                    fragLoadingTimeOut: 20000,
                    fragLoadingMaxRetry: 5
                });

                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.play().catch(() => { v.muted = true; v.play(); });
                });

                // Hata Kurtarma
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
                                console.log("Kritik hata, HLS yeniden başlatılıyor...");
                                hls.destroy();
                                setTimeout(() => {
                                    // Sayfayı yenilemek yerine HLS'i yeniden başlatmayı dene (Opsiyonel)
                                    window.location.reload();
                                }, 3000);
                                break;
                        }
                    }
                });

            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS Native
                v.src = src;
                v.addEventListener('loadedmetadata', () => { v.play().catch(() => { v.muted = true; v.play(); }); });
            }
            window.connectChat(u);
        }
    }
});