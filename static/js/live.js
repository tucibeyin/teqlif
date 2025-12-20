document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    // Logları sunucuya gönder
    function remoteLog(msg) {
        console.log(msg);
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: msg })
        }).catch(() => { });
    }

    // --- YAYINCI MODU ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let ws = null;
        let rec = null;

        async function initStream() {
            try {
                // Android uyumlu sade ayarlar
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: true,
                    video: { facingMode: 'user', width: 640, height: 480, frameRate: 15 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA: Başlatıldı (640x480)");
            } catch (e) { remoteLog("❌ KAMERA HATASI: " + e); alert("Kamera Hatası!"); }
        }
        initStream();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                remoteLog("🔗 WS: Bağlanıyor...");
                ws = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                ws.onopen = () => {
                    remoteLog("✅ WS: Bağlandı. MediaRecorder hazırlanıyor...");
                    startRecording();
                };

                ws.onclose = (e) => remoteLog(`❌ WS KAPANDI: Kod ${e.code}`);
                ws.onerror = (e) => remoteLog("❌ WS HATASI");
            });
        });

        function startRecording() {
            const stream = canvas.captureStream(15);
            if (videoElement.srcObject && videoElement.srcObject.getAudioTracks().length > 0) {
                stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);
            }

            // En sade WebM
            let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 800000 };
            if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm' };

            try {
                rec = new MediaRecorder(stream, options);
            } catch (e) {
                remoteLog("❌ RECORDER INIT HATA: " + e); return;
            }

            rec.onstart = () => remoteLog("✅ RECORDER: Kayıt Başladı (State: " + rec.state + ")");
            rec.onerror = (e) => remoteLog("❌ RECORDER CRASH: " + e.error);

            let packetCount = 0;
            rec.ondataavailable = e => {
                // Veri var mı?
                if (e.data && e.data.size > 0) {
                    // Socket açık mı?
                    if (ws.readyState === WebSocket.OPEN) {
                        ws.send(e.data);
                        packetCount++;
                        // Her 10 pakette bir rapor ver
                        if (packetCount % 5 === 0) {
                            remoteLog(`📤 GÖNDERİLDİ: Pkt #${packetCount} | Boyut: ${e.data.size} B`);
                        }
                    } else {
                        remoteLog(`⚠️ WS KAPALI! Veri çöpe gidiyor. Durum: ${ws.readyState}`);
                    }
                } else {
                    remoteLog("⚠️ RECORDER: Boş veri (0 byte) üretti!");
                }
            };

            rec.start(1000); // 1 saniyede bir veri

            // Canvas Döngüsü (Görüntü akması için zorunlu)
            const ctx = canvas.getContext('2d');
            function draw() {
                if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                requestAnimationFrame(draw);
            }
            draw();
        }

        window.stopBroadcast = () => {
            if (rec) rec.stop();
            if (ws) ws.close();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- İZLEYİCİ MODU ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog(`👀 İZLEYİCİ: ${u} kanalına bağlanıyor...`);
            v.src = `/stream/${u}`;
            v.type = "video/webm";

            v.onplay = () => remoteLog("▶️ VIDEO: Oynatılıyor");
            v.onwaiting = () => remoteLog("⏳ VIDEO: Tamponlanıyor");
            v.onstalled = () => remoteLog("⚠️ VIDEO: Takıldı");

            v.play().catch(e => {
                remoteLog("⚠️ Otoplay engeli, sessiz deneniyor...");
                v.muted = true; v.play();
            });

            // Koparsa
            v.onerror = () => {
                remoteLog("❌ VIDEO HATA: Tekrar deneniyor...");
                setTimeout(() => { v.src = `/stream/${u}?t=${Date.now()}`; v.load(); v.play(); }, 2000);
            };
        }
    }
});