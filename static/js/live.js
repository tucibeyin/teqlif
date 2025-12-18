document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    window.activeHlsInstances = {};
    let rec = null;
    let broadcastWs = null;
    let localStream = null;
    let wakeLock = null;

    async function requestWakeLock() {
        try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { }
    }

    // --- UI/MODERASYON ---
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

    // --- SOHBET ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        function initChatWs() {
            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
            window.CURRENT_SOCKET = ws;
            ws.onmessage = (e) => {
                const d = JSON.parse(e.data);
                if (d.type === 'chat') {
                    const f = document.getElementById(target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`);
                    if (f) { const el = document.createElement('div'); el.className = 'msg'; el.innerHTML = `<b>${d.user}:</b> ${d.msg}`; f.appendChild(el); f.scrollTop = f.scrollHeight; }
                }
            };
            ws.onclose = () => setTimeout(initChatWs, 3000);
        }
        initChatWs();
    };

    // --- 2. YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                localStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true }, video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } } });
                videoElement.srcObject = localStream;
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

                    // 🔥 1 Mbps = Stabilite (Cihazı yormaz) 🔥
                    let opts = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(opts.mimeType)) opts = { mimeType: 'video/webm', videoBitsPerSecond: 1000000 };

                    try { rec = new MediaRecorder(stream, opts); } catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);
                    requestWakeLock();

                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 60000);
                };

                broadcastWs.onclose = () => {
                    // Soket koparsa yayını durdur (Zombi olmasın)
                    if (rec) rec.stop();
                    alert("Bağlantı koptu.");
                    window.location.href = '/';
                };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop();
            if (broadcastWs) broadcastWs.close();
            if (wakeLock) wakeLock.release();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            const src = `/static/hls/${u}/master.m3u8`;
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    liveSyncDurationCount: 3,
                    maxBufferLength: 20,
                    // Hata toleransı
                    manifestLoadingTimeOut: 15000,
                    manifestLoadingMaxRetry: 10,
                });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));

                hls.on(Hls.Events.ERROR, function (event, data) {
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
                v.src = src; v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            window.connectChat(u);
        }
    }
});