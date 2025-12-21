document.addEventListener('DOMContentLoaded', () => {
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    function remoteLog(msg) {
        console.log(msg);
        fetch('/log/client', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg: `[${MODE}] ${msg}` })
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
                    audio: { echoCancellation: true },
                    video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 }, aspectRatio: { ideal: 0.5625 } }
                });
                videoElement.srcObject = stream;
                remoteLog("✅ Kamera 9:16 (720p) Hazır");
            } catch (e) { alert("Kamera Hatası: " + e); }
        }
        initCamera();

        document.getElementById('btn-start-broadcast').addEventListener('click', () => {
            const fd = new FormData();
            fd.append('title', document.getElementById('streamTitle').value || 'Live');
            fd.append('category', document.getElementById('streamCategory').value || 'Genel');

            fetch('/broadcast/start', { method: 'POST', body: fd }).then(res => {
                if (!res.ok) { alert("Sunucu Hatası"); return; }
                document.getElementById('setup-layer').style.display = 'none';
                document.getElementById('live-ui').style.display = 'flex';

                broadcastWs = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                broadcastWs.onopen = () => {
                    const stream = canvas.captureStream(24);
                    stream.addTrack(videoElement.srcObject.getAudioTracks()[0]);

                    let options = { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2000000 };
                    // PC Chrome'da H264 deneyelim
                    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264')) {
                        options = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2000000 };
                        remoteLog("ℹ️ H.264 Codec Seçildi");
                    }

                    rec = new MediaRecorder(stream, options);
                    let packetCount = 0;

                    rec.ondataavailable = e => {
                        if (e.data.size > 0 && broadcastWs.readyState === 1) {
                            if (broadcastWs.bufferedAmount > 500 * 1024) return; // 500KB Buffer
                            broadcastWs.send(e.data);
                            packetCount++;
                            if (packetCount % 20 === 0) remoteLog(`📤 Veri Pkt: ${packetCount}`);
                        }
                    };
                    rec.start(500);

                    setInterval(() => { if (broadcastWs.readyState === 1) fetch('/broadcast/thumbnail', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.3) }) }); }, 30000);
                };
                broadcastWs.onclose = () => { if (rec) rec.stop(); alert("Yayın Kesildi"); location.href = '/'; };
            });
        });
        window.stopBroadcast = () => { if (rec) rec.stop(); if (broadcastWs) broadcastWs.close(); fetch('/broadcast/stop', { method: 'POST' }); location.href = '/'; };
    }

    // --- İZLEYİCİ ---
    else if (MODE === 'watch' && CONFIG.broadcaster) {
        const u = CONFIG.broadcaster;
        const v = document.getElementById(`video-${u}`);
        const src = `/static/hls/${u}/index.m3u8`;

        remoteLog(`👀 İzleyici: ${u}`);

        if (v) {
            v.addEventListener('error', (e) => remoteLog(`❌ Video Err: ${v.error ? v.error.message : '?'}`));

            if (Hls.isSupported()) {
                const hls = new Hls({
                    enableWorker: true,
                    manifestLoadingTimeOut: 15000, // 15sn bekle
                    manifestLoadingMaxRetry: 20, // 20 kere dene
                });
                hls.loadSource(src);
                hls.attachMedia(v);
                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    v.muted = true; v.play().catch(() => { });
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });
                hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        switch (data.type) {
                            case Hls.ErrorTypes.NETWORK_ERROR: hls.startLoad(); break;
                            case Hls.ErrorTypes.MEDIA_ERROR: hls.recoverMediaError(); break;
                            default: hls.destroy(); break;
                        }
                    }
                });
            } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                v.src = src;
                v.addEventListener('loadedmetadata', () => {
                    v.muted = true; v.play().catch(() => { });
                    const ov = document.getElementById(`play-overlay-${u}`);
                    if (ov) ov.style.display = 'none';
                });
            }
        }
    }
});