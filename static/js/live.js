document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg, level = 'INFO') {
        // Konsola da yaz
        console.log(`[${level}] ${msg}`);
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
    window.openModMenu = function (u) { document.getElementById('modMenu').style.display = 'flex'; document.getElementById('mod-target-name').innerText = u; };
    window.closeModMenu = function () { document.getElementById('modMenu').style.display = 'none'; };
    window.restrictUser = function (a, d) {/*...*/ };

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

    // --- 2. YAYINCI (DEBUG MODE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                localStream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 24 } }
                });
                videoElement.srcObject = localStream;
                remoteLog("Kamera Başladı: 640x480 @ 24fps");
            } catch (e) { remoteLog("Kamera Hatası: " + e, 'ERROR'); alert("Kamera Hatası!"); }
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
                    remoteLog("WS Bağlandı. Kayıt Başlatılıyor...");
                    const stream = canvas.captureStream(24);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        remoteLog("H264 desteklenmiyor! VP8 kullanılıyor.", 'WARN');
                        options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    }

                    try { rec = new MediaRecorder(stream, options); } catch (e) {
                        remoteLog("MediaRecorder Hatası: " + e, 'ERROR');
                        return;
                    }

                    rec.onstart = () => remoteLog("MediaRecorder: START");
                    rec.onstop = () => remoteLog("MediaRecorder: STOP");
                    rec.onerror = (e) => remoteLog("MediaRecorder HATA: " + e.error, 'ERROR');

                    let packetCount = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 5000000) {
                                remoteLog(`⚠️ Buffer Dolu! (${broadcastWs.bufferedAmount}) Paket Atlandı.`);
                            } else {
                                broadcastWs.send(e.data);
                                packetCount++;
                                if (packetCount % 30 === 0) {
                                    remoteLog(`Veri Gönderiliyor... Pkt: ${packetCount} | Boyut: ${e.data.size}`);
                                }
                            }
                        } else {
                            if (e.data.size === 0) remoteLog("⚠️ Boş Veri Üretildi");
                        }
                    };

                    rec.start(1000);
                    requestWakeLock();

                    // Önizleme döngüsü
                    function draw() {
                        if (videoElement.readyState === 4) {
                            const ctx = canvas.getContext('2d');
                            ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        }
                        requestAnimationFrame(draw);
                    }
                    draw();

                    // Thumbnail
                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                        }
                    }, 60000);
                };

                broadcastWs.onclose = (e) => {
                    remoteLog(`WS Kapandı! Kod: ${e.code}, Neden: ${e.reason}`, 'ERROR');
                    if (rec) rec.stop();
                    alert("Yayın koptu.");
                    window.location.href = '/';
                };

                broadcastWs.onerror = (e) => {
                    remoteLog("WS Hata Oluştu", 'ERROR');
                };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
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
            remoteLog("İzleyici Bağlanıyor: " + u);

            if (Hls.isSupported()) {
                const hls = new Hls();
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));
                hls.on(Hls.Events.ERROR, (e, d) => {
                    if (d.fatal) remoteLog("HLS Hatası: " + d.type, 'WARN');
                });
            }
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src; v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            window.connectChat(u);
        }
    }
});