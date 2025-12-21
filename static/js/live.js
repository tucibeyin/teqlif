document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    let isIntentionalStop = false;

    // --- YAYINCI KODLARI (Aynı Kaldı) ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true }, video: { facingMode: 'user' }
                });
                videoElement.srcObject = stream;
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Live');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { alert("Hata"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const cameraStream = videoElement.srcObject;
                    let options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                    if (!MediaRecorder.isTypeSupported(options.mimeType)) options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 };

                    try { rec = new MediaRecorder(cameraStream, options); } catch (e) { rec = new MediaRecorder(cameraStream); }
                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 500 * 1024) return;
                            broadcastWs.send(e.data);
                        }
                    };
                    rec.start(1000);

                    setInterval(() => {
                        if (broadcastWs.readyState === 1) {
                            const ctx = canvas.getContext('2d');
                            const vW = videoElement.videoWidth; const vH = videoElement.videoHeight;
                            const targetRatio = 9 / 16; let sW, sH, sX, sY;
                            if (vW / vH > targetRatio) { sH = vH; sW = vH * targetRatio; sX = (vW - sW) / 2; sY = 0; }
                            else { sW = vW; sH = vW / targetRatio; sX = 0; sY = (vH - sH) / 2; }
                            ctx.drawImage(videoElement, sX, sY, sW, sH, 0, 0, canvas.width, canvas.height);
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.4) }) });
                        }
                    }, 15000);
                };
                broadcastWs.onclose = () => { if (!isIntentionalStop) { if (rec) rec.stop(); alert("Kesildi!"); location.href = '/'; } };
            });
        });

        window.stopBroadcast = () => {
            isIntentionalStop = true;
            if (rec) rec.stop(); if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' }).finally(() => location.href = '/');
        };
    }

    // --- İZLEYİCİ (REELS MODU) ---
    else if (MODE === 'watch') {
        const activePlayers = {}; // HLS instance'larını tutar

        // GÖZLEMCİ: Hangi video ekrana girdi?
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                const container = entry.target;
                const username = container.dataset.username;
                const video = container.querySelector('video');

                if (entry.isIntersecting) {
                    // EKRANA GİRDİ: Oynat
                    console.log(`▶️ Oynatılıyor: ${username}`);
                    playStream(username, video);
                } else {
                    // EKRANDAN ÇIKTI: Durdur
                    console.log(`⏸️ Durduruldu: ${username}`);
                    stopStream(username, video);
                }
            });
        }, { threshold: 0.6 }); // %60'ı görünüyorsa aktif say

        // Tüm yayın kutularını gözlemle
        document.querySelectorAll('.feed-item').forEach(item => observer.observe(item));

        function playStream(username, video) {
            const src = `/static/hls/${username}/master.m3u8`;

            // Zaten oynuyorsa dokunma
            if (activePlayers[username]) return;

            if (Hls.isSupported()) {
                const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
                activePlayers[username] = hls;
                hls.loadSource(src);
                hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    video.muted = true; // Otoplay için sessiz
                    video.play().catch(() => { });
                });

                // Hata toleransı
                hls.on(Hls.Events.ERROR, (e, d) => {
                    if (d.fatal && d.type === Hls.ErrorTypes.NETWORK_ERROR) {
                        // Dosya henüz oluşmamış olabilir, bekle ve yeniden dene
                        setTimeout(() => hls.startLoad(), 2000);
                    }
                });

            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = src;
                video.addEventListener('loadedmetadata', () => { video.muted = true; video.play().catch(() => { }); });
            }

            // Kapanış sinyalini dinle
            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${username}`);
            ws.onmessage = (e) => {
                const d = JSON.parse(e.data);
                if (d.type === 'stream_ended') {
                    document.getElementById(`end-screen-${username}`).style.display = 'flex';
                    stopStream(username, video);
                }
            };
            // Soketi de sakla ki çıkınca kapatabilelim
            video.dataset.ws = ws;
        }

        function stopStream(username, video) {
            if (activePlayers[username]) {
                activePlayers[username].destroy();
                delete activePlayers[username];
            }
            video.pause();
            video.src = ""; // Kaynağı boşalt (RAM temizliği)

            // Soketi kapat
            if (video.dataset.ws) {
                video.dataset.ws.close();
                delete video.dataset.ws;
            }
        }
    }
});