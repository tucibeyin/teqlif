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

    window.openModMenu = function (u) {/*...*/ }; window.closeModMenu = function () {/*...*/ };

    window.connectChat = function (target) {
        let streamName = (target === 'broadcast') ? CONFIG.username : target;
        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);
            if (d.type === 'chat') {
                const f = document.getElementById(target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`);
                if (f) { const el = document.createElement('div'); el.className = 'msg'; el.innerHTML = `<b>${d.user}:</b> ${d.msg}`; f.appendChild(el); f.scrollTop = f.scrollHeight; }
            }
        };
    };

    // --- 2. YAYINCI (BU KISIM ZATEN ÇALIŞIYOR) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let wakeLock = null;

        async function requestWakeLock() { try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }

        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA AÇIK");
            } catch (e) { remoteLog("KAMERA HATA: " + e, 'ERROR'); alert("Kamera Hatası!"); }
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
                    remoteLog("✅ WS BAĞLANDI. Kayıt başlıyor...");
                    const stream = canvas.captureStream(24);
                    if (videoElement.srcObject && videoElement.srcObject.getAudioTracks().length > 0) {
                        stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);
                    }

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

                    rec = new MediaRecorder(stream, options);
                    let pkt = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === WebSocket.OPEN) {
                            broadcastWs.send(e.data);
                            pkt++;
                            if (pkt % 20 === 0) remoteLog(`GÖNDERİLDİ: Pkt #${pkt} (${e.data.size}b)`);
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

                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın bitti."); window.location.href = '/'; };
            });
        });

        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/'; };
    }

    // --- 3. İZLEYİCİ (FIXED: OYNAT BUTONU EKLENDİ) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);

        if (v) {
            remoteLog("👀 İZLEYİCİ: Sayfa yüklendi -> " + u);

            // 1. Oynat Butonu Oluştur (Manuel Tetikleme İçin)
            const playBtn = document.createElement("button");
            playBtn.innerHTML = "▶️ YAYINI OYNAT";
            playBtn.style.cssText = "position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); z-index:9999; padding:20px; font-size:20px; background:red; color:white; border:none; border-radius:10px; cursor:pointer;";
            v.parentElement.appendChild(playBtn);

            const startPlayback = () => {
                remoteLog("▶️ OYNATMA İSTEĞİ GÖNDERİLDİ...");
                v.src = `/stream/${u}`;
                v.type = "video/webm";
                v.muted = false; // Ses açık dene
                v.play().then(() => {
                    remoteLog("✅ Oynatma Başladı!");
                    playBtn.style.display = "none";
                }).catch(e => {
                    remoteLog("⚠️ Sesli oynatma engellendi, sessiz deneniyor...");
                    v.muted = true;
                    v.play().then(() => {
                        remoteLog("✅ Sessiz Oynatma Başladı");
                        playBtn.style.display = "none";
                    }).catch(err => {
                        remoteLog("❌ OYNATMA HATASI: " + err);
                        alert("Tarayıcı oynatmayı engelliyor. Lütfen ekrana dokunun.");
                    });
                });
            };

            // Butona basınca başlat
            playBtn.onclick = startPlayback;

            // Otomatik deneme (Sessiz)
            v.muted = true;
            v.play().then(() => {
                playBtn.style.display = "none";
                remoteLog("✅ Otomatik (Sessiz) Başladı");
            }).catch(() => {
                remoteLog("ℹ️ Otomatik başlatma engellendi, buton bekleniyor.");
            });

            // Hata olursa tekrar dene
            v.onerror = () => {
                console.log("Stream hatası, 3sn sonra tekrar deneniyor...");
                setTimeout(() => {
                    v.src = `/stream/${u}?t=${Date.now()}`;
                    v.load();
                    v.play().catch(() => { });
                }, 3000);
            };

            window.connectChat(u);
        }
    }
});