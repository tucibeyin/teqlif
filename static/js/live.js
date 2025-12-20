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

    // --- YAYINCI ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        let broadcastWs = null;
        let rec = null;

        async function initCamera() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: 640, height: 480, frameRate: 24 }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ KAMERA AÇIK");
            } catch (e) { alert("Kamera Hatası!"); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value);
            fd.append('category', document.getElementById('streamCategory').value);

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(() => {
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';
                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    // iOS uyumluluğu için H.264 dene, olmazsa VP8
                    let options;
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 1000000 };
                    } else {
                        options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 1000000 };
                    }

                    try { rec = new MediaRecorder(stream, options); }
                    catch (e) { rec = new MediaRecorder(stream); }

                    rec.ondataavailable = e => { if (e.data.size > 0 && broadcastWs.readyState === 1) broadcastWs.send(e.data); };
                    rec.start(1000);

                    const ctx = canvas.getContext('2d');
                    function draw() {
                        if (videoElement.readyState === 4) ctx.drawImage(videoElement, 0, 0, canvas.width, canvas.height);
                        requestAnimationFrame(draw);
                    }
                    draw();

                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 60000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Bitti"); location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            remoteLog(`👀 İZLEYİCİ: ${u}`);

            // Kaynak Ata
            v.src = `/stream/${u}`;
            v.type = "video/webm";

            // Oynat Butonu
            const playBtn = document.createElement("div");
            playBtn.className = "play-overlay";
            playBtn.innerHTML = `<div class="play-circle"><i class="fa-solid fa-play" style="color:white; font-size:30px; margin-left:5px;"></i></div>`;
            playBtn.onclick = () => {
                v.muted = false;
                v.play().then(() => playBtn.style.display = 'none').catch(() => {
                    v.muted = true; v.play(); playBtn.style.display = 'none';
                });
            };
            v.parentElement.appendChild(playBtn);

            // Otomatik Dene
            v.muted = true;
            v.play().then(() => playBtn.style.display = 'none').catch(() => { });

            // 🔥 AGRESİF HIZLANDIRICI (JUMP START) 🔥
            // Video ilk veriyi aldığında (loadeddata) hemen sona atla
            v.addEventListener('loadeddata', () => {
                if (v.duration === Infinity && v.buffered.length > 0) {
                    v.currentTime = v.buffered.end(v.buffered.length - 1) - 0.1;
                    remoteLog("🚀 BAŞLANGIÇ ZIPLAMASI YAPILDI");
                }
            });

            // Sürekli Kontrol
            setInterval(() => {
                if (v.buffered.length > 0) {
                    const end = v.buffered.end(v.buffered.length - 1);
                    // 2 saniyeden fazla gerideyse atla
                    if (end - v.currentTime > 2) {
                        console.log("⏩ Hızlandırılıyor...");
                        v.currentTime = end - 0.1;
                    }
                }
            }, 3000);

            v.onerror = () => { setTimeout(() => { v.src = `/stream/${u}?t=${Date.now()}`; v.load(); v.play().catch(() => { }); }, 2000); };
        }
    }
});