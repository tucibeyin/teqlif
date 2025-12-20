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

    // --- 2. YAYINCI (BU KISIM ZATEN ÇALIŞIYOR - DOKUNMA) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;
        let wakeLock = null;

        async function requestWakeLock() { try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch (err) { } }

        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 24 } });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA: Açıldı");
            } catch (e) { remoteLog("❌ KAMERA HATA: " + e); alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', 'Canlı'); fd.append('category', 'Genel');
            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    remoteLog("✅ WS BAĞLANDI. Kayıt başlıyor...");
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };
                    rec = new MediaRecorder(stream, options);
                    let pkt = 0;
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === WebSocket.OPEN) {
                            broadcastWs.send(e.data);
                            pkt++;
                            if (pkt % 20 === 0) remoteLog(`📤 GÖNDERİLDİ: Pkt #${pkt} (${e.data.size}b)`);
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
                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 60000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın bitti."); window.location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); window.location.href = '/'; };
    }

    // --- 3. İZLEYİCİ (FORENSIC MODE) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);

        if (v) {
            remoteLog(`👀 İZLEYİCİ: Sayfa yüklendi -> ${u}`);

            // Container'ı temizle ve buton için hazırla
            v.parentElement.style.position = "relative";

            // 1. KOCAMAN OYNAT BUTONU
            const overlay = document.createElement("div");
            overlay.id = "play-overlay";
            overlay.style.cssText = "position:absolute; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.7); display:flex; justify-content:center; align-items:center; z-index:9999; cursor:pointer;";
            overlay.innerHTML = `
                <div style="background:red; color:white; padding:20px 40px; font-size:24px; font-weight:bold; border-radius:50px; box-shadow:0 0 20px rgba(255,0,0,0.5);">
                    ▶️ YAYINI BAŞLAT
                </div>
            `;
            v.parentElement.appendChild(overlay);

            // 2. DETAYLI LOGLAMA
            v.addEventListener('loadstart', () => remoteLog("🎬 VIDEO: Yükleme Başladı (LoadStart)"));
            v.addEventListener('loadedmetadata', () => remoteLog("🎬 VIDEO: Meta Veri Yüklendi (Süre/Boyut)"));
            v.addEventListener('loadeddata', () => remoteLog("🎬 VIDEO: İlk Kare Yüklendi"));
            v.addEventListener('waiting', () => remoteLog("⏳ VIDEO: Tamponlanıyor (Waiting)..."));
            v.addEventListener('playing', () => {
                remoteLog("✅ VIDEO: Oynatılıyor (Playing)!");
                overlay.style.display = 'none'; // Butonu gizle
            });
            v.addEventListener('error', (e) => {
                const err = v.error ? `Kod: ${v.error.code}, Mesaj: ${v.error.message}` : "Bilinmeyen";
                remoteLog(`❌ VIDEO HATA: ${err}`, 'ERROR');
            });

            // 3. OYNATMA FONKSİYONU
            const startStream = () => {
                remoteLog(`🚀 BUTONA BASILDI: ${u} isteniyor...`);
                overlay.innerHTML = "<h2 style='color:white;'>BAĞLANIYOR...</h2>";

                // Kaynak ata
                v.src = `/stream/${u}`;
                v.type = "video/webm";
                v.load();

                // Oynat
                const playPromise = v.play();
                if (playPromise !== undefined) {
                    playPromise.catch(error => {
                        remoteLog("❌ OYNATMA ENGELLENDİ: " + error);
                        overlay.innerHTML = "<div style='background:orange; padding:10px;'>⚠️ Tekrar Dene</div>";
                    });
                }
            };

            overlay.onclick = startStream;
        }
    }
});