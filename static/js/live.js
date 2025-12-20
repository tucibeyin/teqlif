document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg, level = 'INFO') {
        // Konsola da yaz ki telefondan debug edilebilsin
        console.log(`[${level}] ${msg}`);
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: msg, level: level })
        }).catch(() => { });
    }

    let broadcastWs = null;
    let rec = null;
    let localStream = null;

    // --- 2. YAYINCI (DEEP DEBUG MODE) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');

        async function initStream() {
            try {
                localStream = await navigator.mediaDevices.getUserMedia({
                    audio: true,
                    video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 15 }
                });
                videoElement.srcObject = localStream;
                remoteLog("Kamera Açıldı (640x480/15fps)");
            } catch (e) { remoteLog("Kamera Hatası: " + e, 'ERROR'); alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            fetch('/broadcast/start', { method: 'POST', body: new FormData() }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                remoteLog("Socket Bağlanıyor...");
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                broadcastWs.onopen = () => {
                    remoteLog("Socket AÇIK ✅. Kayıt Başlıyor...");
                    startRecording();
                };

                broadcastWs.onclose = (e) => remoteLog(`Socket KAPANDI ❌ Kod: ${e.code}`, 'ERROR');
                broadcastWs.onerror = (e) => remoteLog("Socket HATASI ⚠️", 'ERROR');
            });
        });

        function startRecording() {
            const stream = canvas.captureStream(15);
            if (localStream) stream.addTrack(localStream.getAudioTracks()[0]);

            // En uyumlu formatı bul
            let mimeType = 'video/webm;codecs=vp8';
            if (!MediaRecorder.isTypeSupported(mimeType)) mimeType = 'video/webm';

            remoteLog(`Kayıt Formatı: ${mimeType}`);

            try {
                rec = new MediaRecorder(stream, { mimeType: mimeType, videoBitsPerSecond: 500000 });
            } catch (e) {
                remoteLog("MediaRecorder Başlatılamadı: " + e, 'ERROR');
                return;
            }

            rec.onstart = () => remoteLog("🔴 MediaRecorder State: " + rec.state);
            rec.onstop = () => remoteLog("MediaRecorder Durdu");
            rec.onerror = (e) => remoteLog("Recorder Hatası: " + e.error, 'ERROR');

            let packetCount = 0;

            rec.ondataavailable = e => {
                // 🔥 BURASI KRİTİK: Veri oluşuyor mu?
                if (e.data && e.data.size > 0) {
                    if (broadcastWs.readyState === WebSocket.OPEN) {
                        broadcastWs.send(e.data);
                        packetCount++;
                        if (packetCount % 5 === 0) { // Her 5 pakette bir log at
                            remoteLog(`📤 Veri Gönderildi: ${e.data.size} byte (Pkt: ${packetCount})`);
                        }
                    } else {
                        remoteLog(`⚠️ Socket Hazır Değil: ${broadcastWs.readyState}`, 'WARN');
                    }
                } else {
                    remoteLog("⚠️ BOŞ VERİ OLUŞTU (0 byte)", 'WARN');
                }
            };

            // 1000ms (1 saniye) aralıklarla veri üret
            rec.start(1000);

            // Canvas Döngüsü (Görüntü akması için şart)
            function draw() {
                if (videoElement.readyState === 4) {
                    canvas.getContext('2d').drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                }
                requestAnimationFrame(draw);
            }
            draw();
        }

        window.stopBroadcast = () => {
            if (rec) rec.stop();
            if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- 3. İZLEYİCİ (BASİT WEBM) ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            v.src = `/stream/${u}`;
            v.play().catch(() => { v.muted = true; v.play(); });
            v.onerror = () => setTimeout(() => { v.src = `/stream/${u}?t=${Date.now()}`; v.play(); }, 2000);
        }
    }
});