document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    // Basit Loglama
    function log(msg) {
        console.log("[LOG]", msg);
        fetch('/log/client', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: msg })
        }).catch(() => { });
    }

    // --- YAYINCI MODU ---
    if (MODE === 'broadcast') {
        const videoPreview = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas'); // Thumbnail için
        let ws = null;
        let recorder = null;

        async function startBroadcast() {
            try {
                // 1. Kamerayı Aç (Android uyumlu ayarlar)
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: true,
                    video: { facingMode: 'user', width: 640, height: 480, frameRate: 24 }
                });
                videoPreview.srcObject = stream;
                log("Kamera açıldı.");

                // 2. Yayın Bilgilerini Gönder
                const fd = new FormData();
                fd.append('title', document.getElementById('streamTitle').value || 'Canlı');
                fd.append('category', document.getElementById('streamCategory').value || 'Genel');
                await fetch('/broadcast/start', { method: 'POST', body: fd });

                // 3. Socket Bağla
                ws = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                ws.onopen = () => {
                    log("Socket bağlandı. Kayıt başlıyor...");

                    // 4. Kaydediciyi Başlat (WebM/VP8)
                    // H.264 zorlamıyoruz, tarayıcı neyi destekliyorsa onu kullansın.
                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 800000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) {
                        options = { mimeType: 'video/webm' }; // Fallback
                    }

                    recorder = new MediaRecorder(stream, options);

                    recorder.ondataavailable = (event) => {
                        if (event.data.size > 0 && ws.readyState === WebSocket.OPEN) {
                            ws.send(event.data);
                        }
                    };

                    recorder.start(1000); // 1 saniyede bir veri gönder
                    log("Yayın başladı! 🚀");
                };

                ws.onclose = () => {
                    log("Socket kapandı.");
                    alert("Yayın bağlantısı kesildi.");
                    location.href = "/";
                };

            } catch (err) {
                log("HATA: " + err);
                alert("Hata: " + err);
            }
        }

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            document.getElementById('setup-layer').style.display = 'none';
            startBroadcast();
        });

        window.stopBroadcast = () => {
            if (recorder) recorder.stop();
            if (ws) ws.close();
            fetch('/broadcast/stop', { method: 'POST' });
            location.href = "/";
        };
    }

    // --- İZLEYİCİ MODU ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const videoPlayer = document.getElementById(`video-${CONFIG.broadcaster}`);
        if (videoPlayer) {
            log("İzleyici modu başlatılıyor...");

            // Statik dosya değil, Streaming Endpoint kullanıyoruz
            videoPlayer.src = `/stream/${CONFIG.broadcaster}`;
            videoPlayer.type = "video/webm";

            videoPlayer.play().catch(e => {
                console.log("Otoplay hatası:", e);
                videoPlayer.muted = true;
                videoPlayer.play();
            });

            // Hata olursa (Yayın koptuysa) yeniden dene
            videoPlayer.onerror = () => {
                console.log("Hata oluştu, tekrar deneniyor...");
                setTimeout(() => {
                    videoPlayer.src = `/stream/${CONFIG.broadcaster}?t=${Date.now()}`;
                    videoPlayer.load();
                    videoPlayer.play();
                }, 3000);
            };
        }
    }
});