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

    // --- 2. YAYINCI (ANDROID NATIVE MODE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                localStream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 24 } }
                });
                videoElement.srcObject = localStream;
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
                    remoteLog("Yayın Başlıyor (VP8 Native)...");
                    const stream = canvas.captureStream(24);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    // 🔥 ANDROID İÇİN EN GÜVENLİ AYAR: VP8 🔥
                    // H.264 zorlamıyoruz, VP8 Android'in doğal formatıdır.
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };

                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        remoteLog("VP8 desteklenmiyor, varsayılan deneniyor.", 'WARN');
                        options = { mimeType: 'video/webm', videoBitsPerSecond: 1000000 };
                    }

                    try { rec = new MediaRecorder(stream, options); } catch (e) {
                        remoteLog("Encoder Hatası: " + e, 'ERROR');
                        return;
                    }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // Buffer koruması (5MB)
                            if (broadcastWs.bufferedAmount > 5000000) {
                                console.warn("Ağ yavaş, paket atlandı.");
                            } else {
                                broadcastWs.send(e.data);
                            }
                        }
                    };

                    rec.start(1000);
                    requestWakeLock();

                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                        }
                    }, 60000);
                };

                broadcastWs.onclose = () => {
                    if (rec) rec.stop();
                    alert("Yayın koptu.");
                    window.location.href = '/';
                };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (WEBM PLAYER) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog("İzleyici: " + u);
            // Sunucu raw WebM yazıyor, biz de onu okuyoruz
            v.src = `/stream/${u}`;
            v.type = "video/webm";

            v.play().catch(() => { v.muted = true; v.play(); });

            // Koparsa tekrar bağlan
            v.onerror = () => {
                setTimeout(() => {
                    v.src = `/stream/${u}?t=${Date.now()}`;
                    v.load(); v.play();
                }, 2000);
            };

            window.connectChat(u);
        }
    }
});