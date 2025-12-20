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

    // --- 2. YAYINCI (LOGLU + VP8 GÜVENLİ MOD) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let wakeLock = null;

        async function requestWakeLock() { try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }

        async function initStream() {
            try {
                // 480p ideal ve güvenli çözünürlük
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA: Açıldı (640x480)");
            } catch (e) { remoteLog("❌ KAMERA HATA: " + e, 'ERROR'); alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(response => {
                if (!response.ok) { remoteLog("BAŞLAT HATA: Sunucu " + response.status, 'ERROR'); return; }

                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                window.connectChat('broadcast');

                remoteLog("🔗 WS: Bağlanıyor...");
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                broadcastWs.onopen = () => {
                    remoteLog("✅ WS: Bağlandı. Kayıt başlıyor...");
                    const stream = canvas.captureStream(24);
                    // Ses izini ekle
                    if (videoElement.srcObject && videoElement.srcObject.getAudioTracks().length > 0) {
                        stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);
                    }

                    // Android için en güvenli format: VP8
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

                    try {
                        rec = new MediaRecorder(stream, options);
                    } catch (e) {
                        remoteLog("❌ RECORDER INIT HATA: " + e, 'FATAL'); return;
                    }

                    let packetCount = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === WebSocket.OPEN) {
                            broadcastWs.send(e.data);
                            packetCount++;
                            if (packetCount % 20 === 0) {
                                remoteLog(`📤 GÖNDERİLDİ: Pkt #${packetCount} | Boyut: ${e.data.size}`);
                            }
                        } else if (broadcastWs.readyState !== WebSocket.OPEN) {
                            remoteLog(`⚠️ WS KAPALI: Veri gönderilemedi.`, 'WARN');
                        }
                    };

                    rec.start(1000); // 1 saniyede bir gönder
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

                broadcastWs.onclose = (e) => {
                    remoteLog(`❌ WS KAPANDI: Kod ${e.code}`, 'ERROR');
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

    // --- 3. İZLEYİCİ (BUTONLU + LOGLU) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog(`👀 İZLEYİCİ: Sayfa yüklendi -> ${u}`);

            // --- OYNAT BUTONU EKLE (KURTARICI) ---
            const playBtn = document.createElement("div");
            playBtn.innerHTML = "<i class='fa-solid fa-play'></i> YAYINI BAŞLAT";
            playBtn.style.cssText = "position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); z-index:9999; padding:15px 30px; font-size:18px; font-weight:bold; background:#e74c3c; color:white; border-radius:30px; cursor:pointer; box-shadow: 0 5px 20px rgba(0,0,0,0.5); display:flex; align-items:center; gap:10px;";
            v.parentElement.appendChild(playBtn);

            const startPlayback = () => {
                remoteLog("▶️ OYNATMA: Butona basıldı, video isteniyor...");
                playBtn.innerHTML = "<i class='fa-solid fa-circle-notch fa-spin'></i> BAĞLANIYOR...";

                // Canlı akış adresi
                v.src = `/stream/${u}`;
                v.type = "video/webm";
                v.load(); // Yüklemeyi zorla

                const playPromise = v.play();

                if (playPromise !== undefined) {
                    playPromise.then(() => {
                        remoteLog("✅ VİDEO: Oynatma Başladı!");
                        playBtn.style.display = "none";
                    }).catch(error => {
                        remoteLog("❌ OYNATMA HATASI: " + error);
                        playBtn.innerHTML = "⚠️ HATA - TEKRAR DENE";
                        // Otomatik olarak sessiz modda dene
                        v.muted = true;
                        v.play().then(() => {
                            remoteLog("✅ VİDEO: Sessiz modda başladı.");
                            playBtn.style.display = "none";
                        });
                    });
                }
            };

            // Butona tıklayınca başlat
            playBtn.onclick = startPlayback;

            // Arka planda otomatik deneme (Sessiz)
            v.muted = true;
            v.play().then(() => {
                remoteLog("✅ OTO-BAŞLAT: Başarılı (Sessiz)");
                playBtn.style.display = "none";
            }).catch(() => {
                remoteLog("ℹ️ OTO-BAŞLAT: Engellendi, buton bekleniyor.");
            });

            // Video Durum Logları
            v.onwaiting = () => remoteLog("⏳ VİDEO: Tamponlanıyor...");
            v.onplaying = () => remoteLog("▶️ VİDEO: Akıyor...");

            // Hata Yönetimi
            v.onerror = () => {
                console.log("Stream hatası, 2sn sonra tekrar deneniyor...");
                setTimeout(() => {
                    // Cache'i kırmak için timestamp ekle
                    v.src = `/stream/${u}?t=${Date.now()}`;
                    v.play().catch(() => { });
                }, 2000);
            };

            window.connectChat(u);
        }
    }
});