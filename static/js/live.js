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

    // --- UI ---
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

    // --- 2. YAYINCI (STABLE BUFFER MODE) ---
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
                        width: { ideal: 640 },
                        height: { ideal: 480 },
                        frameRate: { ideal: 24, max: 30 }
                    }
                });
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
                    remoteLog("Yayın Başladı (Buffer: 5MB)");
                    const stream = canvas.captureStream(24);
                    if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

                    // Codec Seçimi: H.264 > VP8
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    }

                    try { rec = new MediaRecorder(stream, options); } catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            // 🔥 TAMPON SINIRI 5MB (YETERLİ ALAN) 🔥
                            // 5.000.000 byte = 5MB. Bu RAM'i yormaz ama ağı rahatlatır.
                            if (broadcastWs.bufferedAmount > 5000000) {
                                console.warn("Ağ çok kötü! Paket atlanıyor...");
                            } else {
                                broadcastWs.send(e.data);
                            }
                        }
                    };

                    rec.start(1000);
                    requestWakeLock();

                    setInterval(() => {
                        if (broadcastWs.readyState === 1 && broadcastWs.bufferedAmount === 0) {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                        }
                    }, 60000);
                };

                broadcastWs.onclose = () => {
                    remoteLog("WS Kapandı", 'WARN');
                    if (rec) rec.stop();
                    alert("Yayın koptu.");
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
            const src = `/static/hls/${u}/master.m3u8`;
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    manifestLoadingTimeOut: 20000
                });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src; v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            window.connectChat(u);
        }
    }
});