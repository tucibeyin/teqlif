document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    window.activeHlsInstances = {};
    let AUCTION_ACTIVE = CONFIG.auctionActive;
    let activeModTarget = null;
    let localStream = null;
    let rec = null;
    let broadcastWs = null;

    // --- KAMERA BAŞLATMA ---
    if (MODE === 'broadcast') {
        const videoElement = document.getElementById('preview');
        const canvas = document.getElementById('broadcast-canvas');
        const ctx = canvas.getContext('2d', { alpha: false });

        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true },
                    video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }
                });
                localStream = stream; videoElement.srcObject = stream;

                // Canvas Döngüsü (30 FPS)
                function draw() {
                    if (videoElement.readyState === 4) {
                        const vRatio = videoElement.videoWidth / videoElement.videoHeight;
                        const cRatio = canvas.width / canvas.height;
                        let dw, dh, sx, sy;
                        if (vRatio > cRatio) { dh = canvas.height; dw = dh * vRatio; sx = (canvas.width - dw) / 2; sy = 0; }
                        else { dw = canvas.width; dh = dw / vRatio; sx = 0; sy = (canvas.height - dh) / 2; }
                        ctx.drawImage(videoElement, sx, sy, dw, dh);
                    }
                    requestAnimationFrame(draw);
                }
                draw();

                // Ses Kaynakları
                const devices = await navigator.mediaDevices.enumerateDevices();
                const audioSelect = document.getElementById('audioSource');
                if (audioSelect) {
                    audioSelect.innerHTML = "";
                    devices.filter(d => d.kind === 'audioinput').forEach(d => {
                        const opt = document.createElement('option'); opt.value = d.deviceId; opt.text = d.label || 'Mikrofon'; audioSelect.appendChild(opt);
                    });
                }
            } catch (err) { alert("Kamera erişimi hatası!"); }
        }
        initStream();

        // --- YAYIN BAŞLAT BUTONU ---
        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', function () {
                const title = document.getElementById('streamTitle').value;
                const category = document.getElementById('streamCategory').value;
                if (!title) { alert("Başlık girin!"); return; }

                const formData = new FormData();
                formData.append('title', title); formData.append('category', category);

                fetch('/broadcast/start', { method: 'POST', body: formData }).then(res => res.json()).then(data => {
                    document.getElementById('setup-layer').style.display = 'none';
                    document.getElementById('live-ui').style.display = 'flex';
                    window.connectChat('broadcast');

                    broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

                    broadcastWs.onopen = () => {
                        const canvasStream = canvas.captureStream(30);
                        if (localStream) {
                            const audioTracks = localStream.getAudioTracks();
                            if (audioTracks.length > 0) canvasStream.addTrack(audioTracks[0]);
                        }

                        // 🔥 OTOMATİK CODEC SEÇİMİ 🔥
                        let mimeType = 'video/webm';
                        let options = { mimeType: mimeType, videoBitsPerSecond: 1500000 }; // 1.5 Mbps

                        if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                            options.mimeType = 'video/webm;codecs=h264';
                        } else if (MediaRecorder.isTypeSupported('video/webm;codecs=vp8')) {
                            options.mimeType = 'video/webm;codecs=vp8';
                        }

                        try { rec = new MediaRecorder(canvasStream, options); }
                        catch (e) { rec = new MediaRecorder(canvasStream); } // Fallback

                        rec.ondataavailable = e => {
                            if (e.data.size > 0 && broadcastWs.readyState === 1) {
                                broadcastWs.send(e.data);
                            }
                        };

                        rec.start(1000); // 1 saniyelik paketler

                        // Thumbnail
                        setInterval(() => {
                            fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.5), timestamp: Date.now() }) });
                        }, 60000);
                    };
                });
            });
        }

        window.stopBroadcast = function () {
            if (rec) rec.stop();
            if (broadcastWs) broadcastWs.close();
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };
    }

    // --- İZLEYİCİ ---
    if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        if (v) {
            const src = `/static/hls/${u}/master.m3u8`;
            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: true,
                    backBufferLength: 0,
                    liveSyncDurationCount: 3, // 3 parça geriden gel (Donmayı önler)
                });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src;
                v.addEventListener('loadedmetadata', () => v.play().catch(() => { v.muted = true; v.play() }));
            }
            window.connectChat(u);
        }
    }

    // --- DİĞER UI FONKSİYONLARI (Kısaltıldı, aynısı) ---
    window.connectChat = function (t) {/* Eski Chat Kodu Buraya Gelebilir veya aynısı */ };
    window.openModMenu = function (u) { document.getElementById('modMenu').style.display = 'flex'; activeModTarget = u; document.getElementById('mod-target-name').innerText = u; };
    window.closeModMenu = function () { document.getElementById('modMenu').style.display = 'none'; };
    window.restrictUser = function (a, d) { /* ... */ };
    // (Diğer fonksiyonlar: toggleAuction, sendGift vs. aynen kalabilir)
});