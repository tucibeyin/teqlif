document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    // 🔥 LOGLARI SUNUCUYA GÖNDERME FONKSİYONU 🔥
    function remoteLog(msg, level = 'INFO') {
        // Konsola da yaz
        console.log(`[REMOTE] ${msg}`);

        // Sunucuya gönder
        fetch('/log/client', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: msg, level: level })
        }).catch(e => { }); // Hata verirse yut, döngüye girmesin
    }

    // Konsol hatalarını yakala
    window.onerror = function (message, source, lineno, colno, error) {
        remoteLog(`GLOBAL JS HATASI: ${message} @ ${lineno}`, 'ERROR');
    };

    window.CURRENT_SOCKET = null;
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

    // --- SOHBET ---
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        function initChatWs() {
            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
            window.CURRENT_SOCKET = ws;
            ws.onopen = () => remoteLog(`Chat Bağlandı: ${streamName}`);
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
                remoteLog("Kamera izni isteniyor...");
                localStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true }, video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } } });
                videoElement.srcObject = localStream;
                remoteLog("Kamera açıldı!");

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
            } catch (e) {
                remoteLog("Kamera Hatası: " + e.message, 'ERROR');
                alert("Kamera Hatası!");
            }
        }
        initStream();

        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', () => {
                remoteLog("Butona basıldı.");
                const fd = new FormData();
                fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
                fd.append('category', document.getElementById('streamCategory').value || 'Genel');

                remoteLog("Sunucuya istek gönderiliyor...");
                fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                    if (res.ok) {
                        remoteLog("Sunucu ONAYLADI.");
                        document.getElementById('setup-layer').style.display = 'none';
                        document.getElementById('live-ui').style.display = 'flex';
                        window.connectChat('broadcast');
                        startBroadcastSession();
                    } else {
                        remoteLog("Sunucu HATASI: " + res.status, 'ERROR');
                    }
                }).catch(err => remoteLog("Fetch Hatası: " + err, 'ERROR'));
            });
        }

        function startBroadcastSession() {
            if (broadcastWs) broadcastWs.close();
            if (rec && rec.state !== 'inactive') rec.stop();

            remoteLog("WS Bağlantısı başlatılıyor...");
            broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

            broadcastWs.onopen = () => {
                remoteLog("WS Bağlandı (Open)");
                const stream = canvas.captureStream(30);
                if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                let opts = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                if (!MediaRecorder.isTypeSupported(opts.mimeType)) {
                    remoteLog("VP8 desteklenmiyor, varsayılana dönüldü.", 'WARN');
                    opts = { mimeType: 'video/webm' };
                }

                try { rec = new MediaRecorder(stream, opts); }
                catch (e) {
                    remoteLog("Recorder Init Hatası: " + e, 'ERROR');
                    rec = new MediaRecorder(stream);
                }

                rec.ondataavailable = e => {
                    if (e.data.size > 0 && broadcastWs.readyState === 1) {
                        broadcastWs.send(e.data);
                    }
                };

                rec.start(1000);
                remoteLog("Recorder Başladı (1000ms)");
                requestWakeLock();

                setInterval(() => {
                    if (broadcastWs.readyState === 1) {
                        fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                    }
                }, 60000);
            };

            broadcastWs.onclose = (e) => {
                remoteLog("WS Koptu! Kod: " + e.code, 'WARN');
                if (rec) rec.stop();
                alert("Yayın bağlantısı koptu.");
                window.location.reload();
            };

            broadcastWs.onerror = (e) => remoteLog("WS Hatası Oluştu!", 'ERROR');
        }

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
            const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`; // Cache Buster
            remoteLog("İzleyici Modu: " + u);

            if (Hls.isSupported()) {
                remoteLog("HLS.js Destekleniyor");
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    liveSyncDurationCount: 3,
                    maxBufferLength: 20,
                    manifestLoadingTimeOut: 20000,
                    manifestLoadingMaxRetry: 10,
                });
                hls.loadSource(src);
                hls.attachMedia(v);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    remoteLog("Manifest Ayrıştırıldı");
                    v.play().catch(e => remoteLog("Oto-oynatma engellendi: " + e));
                });

                hls.on(Hls.Events.ERROR, function (event, data) {
                    if (data.fatal) {
                        remoteLog("HLS Hatası: " + data.type, 'ERROR');
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR: hls.startLoad(); break;
                            case Hls.ErrorTypes.MEDIA_ERROR: hls.recoverMediaError(); break;
                            default: hls.destroy(); break;
                        }
                    }
                });
            }
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                remoteLog("Native HLS Player");
                v.src = src;
                v.addEventListener('loadedmetadata', () => v.play().catch(e => remoteLog("iOS Oynatma Hatası: " + e)));
            }
            window.connectChat(u);
        }
    }
});