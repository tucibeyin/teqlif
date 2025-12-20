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

    // --- 2. YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let wakeLock = null;

        async function requestWakeLock() { try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }

        async function initStream() {
            try {
                // 480p idealdir
                const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 } });
                videoElement.srcObject = stream;
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
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // Android uyumlu VP8
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

                    rec = new MediaRecorder(stream, options);
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 5000000) console.warn("Drop frame");
                            else broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);
                    requestWakeLock();

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();

                    setInterval(() => {
                        if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                    }, 60000);
                };

                broadcastWs.onclose = () => {
                    if (rec) rec.stop();
                    alert("Yayın bitti.");
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

    // --- 3. İZLEYİCİ (CANLI AKIŞ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog("İzleyici: " + u);
            // Statik dosya değil, API'den canlı akış
            v.src = `/stream/${u}`;
            v.type = "video/webm";

            v.play().catch(e => {
                console.log("Oynatma hatası:", e);
                v.muted = true;
                v.play();
            });

            // Yayın biterse veya koparsa
            v.onerror = () => {
                setTimeout(() => {
                    v.src = `/stream/${u}?t=${Date.now()}`;
                    v.load(); v.play();
                }, 3000);
            };
            window.connectChat(u);
        }
    }
});