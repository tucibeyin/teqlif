document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    // 🔥 LOG 🔥
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
    let wakeLock = null;

    // --- EKRAN KİLİDİ ---
    async function requestWakeLock() {
        try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { }
    }

    // --- UI FONKSİYONLARI ---
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
                localStream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }
                });
                videoElement.srcObject = localStream;
                log("Kamera Hazır.");

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
                log("Kamera Hatası: " + e);
                alert("Kamera başlatılamadı! HTTPS kullandığınızdan emin olun.");
            }
        }
        initStream();

        // 🔥 BUTON DİNLLEYİCİSİ 🔥
        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', () => {
                log("Butona basıldı, istek hazırlanıyor...");

                const titleVal = document.getElementById('streamTitle').value;
                const catVal = document.getElementById('streamCategory').value;

                if (!titleVal) { alert("Lütfen bir başlık girin!"); return; }

                // Butonu kilitle
                startBtn.disabled = true;
                startBtn.innerText = "Başlatılıyor...";

                const fd = new FormData();
                fd.append('title', titleVal);
                fd.append('category', catVal);

                log("Sunucuya POST isteği gönderiliyor...");

                fetch('/broadcast/start', { method: 'POST', body: fd })
                    .then(res => res.json())
                    .then(data => {
                        log("Sunucu yanıt verdi: " + data.status);
                        document.getElementById('setup-layer').style.display = 'none';
                        document.getElementById('live-ui').style.display = 'flex';
                        window.connectChat('broadcast');

                        broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                        broadcastWs.onopen = () => {
                            log("WebSocket Bağlandı ✅");
                            const stream = canvas.captureStream(30);
                            if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                            let opts = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                            if (!MediaRecorder.isTypeSupported(opts.mimeType)) opts = { mimeType: 'video/webm' };

                            try { rec = new MediaRecorder(stream, opts); } catch (e) { rec = new MediaRecorder(stream); }

                            rec.ondataavailable = e => {
                                if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data);
                            };
                            rec.start(1000);
                            requestWakeLock();

                            setInterval(() => {
                                fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.5) }) });
                            }, 60000);
                        };

                        broadcastWs.onerror = (e) => log("WS Hatası!");
                        broadcastWs.onclose = () => {
                            log("WS Kapandı!");
                            alert("Yayın bağlantısı koptu.");
                            window.location.reload();
                        };
                    })
                    .catch(err => {
                        log("Fetch Hatası: " + err);
                        alert("Sunucuya bağlanılamadı.");
                        startBtn.disabled = false;
                        startBtn.innerText = "YAYINI BAŞLAT 🚀";
                    });
            });
        } else {
            log("HATA: Başlat butonu bulunamadı!");
        }

        window.stopBroadcast = () => {
            if (rec) rec.stop();
            if (broadcastWs) broadcastWs.close();
            if (wakeLock) wakeLock.release();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (TOLERANSLI) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`;
            log("Yayın aranıyor: " + u);

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    liveSyncDurationCount: 3,
                    maxBufferLength: 30,
                    manifestLoadingTimeOut: 20000,
                    manifestLoadingMaxRetry: 10,
                });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    log("Manifest bulundu, oynatılıyor.");
                    v.play().catch(() => { v.muted = true; v.play() });
                });

                hls.on(Hls.Events.ERROR, function (event, data) {
                    if (data.fatal) {
                        log("Hata: " + data.type + " - Tekrar deneniyor.");
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR: hls.startLoad(); break;
                            case Hls.ErrorTypes.MEDIA_ERROR: hls.recoverMediaError(); break;
                            default: hls.destroy(); break;
                        }
                    }
                });
            }
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src;
                v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            window.connectChat(u);
        }
    }
});