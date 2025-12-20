document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg, level = 'INFO') {
        console.log(`[${level}] ${msg}`);
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

    // --- 2. YAYINCI (NATIVE ANDROID MODE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let wakeLock = null;

        async function requestWakeLock() { try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }

        async function initStream() {
            try {
                // Android için en güvenli çözünürlük: 640x480 (4:3) veya 640x360 (16:9)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("Kamera Açıldı ✅");
            } catch (e) { remoteLog("Kamera Hatası: " + e, 'ERROR'); alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            // 🔥 DÜZELTME: Form verilerini ekle 🔥
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(response => {
                if (!response.ok) {
                    remoteLog("Sunucu Hatası: " + response.status, 'ERROR');
                    alert("Yayın başlatılamadı. Sunucu hatası.");
                    return;
                }

                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                window.connectChat('broadcast');

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                broadcastWs.onopen = () => {
                    remoteLog("WS Bağlandı. Kayıt Başlıyor...");
                    const stream = canvas.captureStream(24);
                    // Ses izini ekle
                    if (videoElement.srcObject && videoElement.srcObject.getAudioTracks().length > 0) {
                        stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);
                    }

                    // 🔥 NATIVE CODEC (Zorlama Yok) 🔥
                    // 'video/webm' Android'in en doğal formatıdır. Codec belirtmeyerek tarayıcının en iyi bildiği işi yapmasına izin veriyoruz.
                    let options = { mimeType: 'video/webm', videoBitsPerSecond: 1000000 };

                    try {
                        rec = new MediaRecorder(stream, options);
                    } catch (e) {
                        remoteLog("MediaRecorder Başlatılamadı: " + e, 'ERROR');
                        // Fallback (Seçenekleri kaldır)
                        try { rec = new MediaRecorder(stream); } catch (err) { remoteLog("Fallback de başarısız: " + err, 'FATAL'); return; }
                    }

                    rec.ondataavailable = e => {
                        if (e.data && e.data.size > 0) {
                            if (broadcastWs.readyState === WebSocket.OPEN) {
                                broadcastWs.send(e.data);
                            }
                        } else {
                            // Boş veri gelirse uyar
                            console.warn("Boş veri paketi");
                        }
                    };

                    // 1000ms (1 saniye) aralıklarla veri gönder
                    rec.start(1000);
                    requestWakeLock();

                    // Canvas Döngüsü (Görüntüyü Akıtmak İçin Şart)
                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) {
                            ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        }
                        requestAnimationFrame(draw);
                    }
                    draw();

                    // Thumbnail
                    setInterval(() => {
                        if (broadcastWs.readyState === WebSocket.OPEN) {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) });
                        }
                    }, 60000);
                };

                broadcastWs.onclose = () => {
                    if (rec) rec.stop();
                    alert("Yayın bitti veya bağlantı koptu.");
                    window.location.href = '/';
                };
            });
        });

        window.stopBroadcast = () => {
            if (rec) rec.stop();
            if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (RAW STREAM PLAYER) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog("İzleyici: " + u);
            // Canlı akış endpoint'ini kullan
            v.src = `/stream/${u}`;
            v.type = "video/webm";

            v.play().catch(e => {
                console.log("Otoplay engellendi, sessiz deneniyor...", e);
                v.muted = true;
                v.play();
            });

            // Yayın koparsa veya biterse tekrar dene
            v.onerror = () => {
                setTimeout(() => {
                    v.src = `/stream/${u}?t=${Date.now()}`; // Cache breaker
                    v.load();
                    v.play();
                }, 3000);
            };

            window.connectChat(u);
        }
    }
});