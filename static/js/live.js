document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg, level = 'INFO') {
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: msg, level: level })
        }).catch(() => { });
    }

    window.CURRENT_SOCKET = null;
    let rec = null;
    let broadcastWs = null;
    let localStream = null;
    let wakeLock = null;

    async function requestWakeLock() {
        try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { }
    }

    // --- UI Helpers ---
    window.openModMenu = function (u) {/*...*/ }; window.closeModMenu = function () {/*...*/ };
    window.restrictUser = function (a, d) {/*...*/ }; window.updatePriceDisplay = function (a, t, n) {/*...*/ };
    window.toggleAuction = function () {/*...*/ }; window.openResetModal = function () {/*...*/ };
    window.closeResetModal = function () {/*...*/ }; window.confirmReset = function () {/*...*/ };
    window.sendBid = function (t, a) {/*...*/ }; window.sendManualBid = function (t) {/*...*/ };
    window.sendMsg = function (t) { const i = document.getElementById('chat-input-' + (t == 'broadcast' ? 'broadcast' : t)); if (i && i.value.trim()) { window.CURRENT_SOCKET.send(i.value); i.value = ''; i.focus(); } };
    window.openGiftMenu = function (u) { document.getElementById('giftMenu').style.display = 'block'; };
    window.closeGiftMenu = function () { document.getElementById('giftMenu').style.display = 'none'; };
    window.sendGift = function (t) {/*...*/ }; window.toggleFollow = function (u) {/*...*/ };
    window.unmuteVideo = function (u) { const v = document.getElementById('video-' + u); if (v) { v.muted = false; } };

    // --- CHAT ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        window.CURRENT_SOCKET = ws;
        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);
            if (d.type === 'chat') {
                const f = document.getElementById(target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`);
                if (f) { const el = document.createElement('div'); el.className = 'msg'; el.innerHTML = `<b>${d.user}:</b> ${d.msg}`; f.appendChild(el); f.scrollTop = f.scrollHeight; }
            }
        };
    };

    // --- 2. YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                localStream = await navigator.mediaDevices.getUserMedia({
                    audio: {
                        echoCancellation: true,
                        noiseSuppression: true
                    },
                    video: {
                        facingMode: 'user',
                        width: { ideal: 1280 },
                        height: { ideal: 720 },
                        frameRate: { ideal: 30 }
                    }
                });
                videoElement.srcObject = localStream;
                // Önizlemeyi çiz
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
            } catch (e) { remoteLog("Kamera Hatası: " + e, 'ERROR'); alert("Kamera başlatılamadı!"); }
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
                    remoteLog("Yayın Başlatılıyor (H.264 Öncelikli)...");
                    const stream = canvas.captureStream(30);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    // 🔥 KRİTİK: H.264 ZORLAMA 🔥
                    // Bu sıralama evrensel uyumluluk için çok önemlidir.
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 1500000 };

                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        remoteLog("H.264 desteklenmiyor, VP8'e geçiliyor (iOS'ta çalışmayabilir).", 'WARN');
                        options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1500000 };
                    }
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        options = { mimeType: 'video/webm' }; // Varsayılan
                    }

                    remoteLog("Seçilen Codec: " + options.mimeType);

                    try { rec = new MediaRecorder(stream, options); } catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // Emniyet Sübabı: İnternet çok kötüyse gönderme
                            if (broadcastWs.bufferedAmount > 250000) {
                                console.warn("Buffer dolu, paket atlandı.");
                            } else {
                                broadcastWs.send(e.data);
                            }
                        }
                    };

                    // Veriyi 1 saniyelik parçalar halinde gönder
                    rec.start(1000);
                    requestWakeLock();

                    setInterval(() => {
                        if (broadcastWs.readyState === 1 && broadcastWs.bufferedAmount === 0) {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 60000);
                };

                broadcastWs.onclose = () => {
                    remoteLog("WS Kapandı", 'WARN');
                    if (rec) rec.stop();
                    alert("Bağlantı kesildi.");
                    window.location.href = '/';
                };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            if (wakeLock) wakeLock.release();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (HLS) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            const src = `/static/hls/${u}/stream.m3u8`;
            remoteLog("İzleyici: " + u);

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));

                // Hata Yönetimi
                hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR:
                                hls.startLoad();
                                break;
                            case Hls.ErrorTypes.MEDIA_ERROR:
                                hls.recoverMediaError();
                                break;
                            default:
                                hls.destroy();
                                break;
                        }
                    }
                });
            }
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                // iOS / Safari
                v.src = src;
                v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            window.connectChat(u);
        }
    }
});