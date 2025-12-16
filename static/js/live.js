document.addEventListener('DOMContentLoaded', () => {
    // Global ayarları al
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    window.CURRENT_SOCKET = null;
    let AUCTION_ACTIVE = CONFIG.auctionActive;

    // --- ORTAK FONKSİYONLAR ---

    window.unmuteVideo = function (u) {
        const v = document.getElementById(`video-${u}`);
        if (v) {
            v.muted = false;
            v.volume = 1.0;
            const hint = v.parentElement.querySelector('.tap-hint');
            if (hint) hint.style.display = 'none';
        }
    }

    function updatePriceDisplay(amount, target, bidderName) {
        const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`;
        const el = document.getElementById(id);
        if (el) {
            el.innerText = amount;
            el.classList.remove("blink-anim");
            void el.offsetWidth;
            el.classList.add("blink-anim");
        }

        const leaderRowId = target === 'broadcast' ? 'leader-display-broadcast' : `leader-display-${target}`;
        const leaderRow = document.getElementById(leaderRowId);
        if (leaderRow) {
            if (bidderName) {
                leaderRow.style.display = 'flex';
                leaderRow.querySelector('.name').innerText = bidderName;
            } else {
                leaderRow.style.display = 'none';
            }
        }
    }

    function connectChat(target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();

        let sName = target === 'broadcast' ? CONFIG.username : target;

        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${sName}`);
        window.CURRENT_SOCKET = ws;

        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);

            if (d.type === 'init') {
                updatePriceDisplay(d.price, target, d.leader);
                return;
            }

            if (d.type === 'auction_state') {
                const layer = document.getElementById(target === 'broadcast' ? '' : `bid-layer-${target}`);
                const board = document.getElementById(target === 'broadcast' ? '' : `price-board-${target}`);
                if (layer) layer.style.display = d.active ? 'flex' : 'none';
                if (board) board.style.display = d.active ? 'flex' : 'none';
                return;
            }

            if (d.type === 'reset_auction') {
                updatePriceDisplay(0, target, null);
                const bidFeedId = target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`;
                const bidFeed = document.getElementById(bidFeedId);
                if (bidFeed) bidFeed.innerHTML = '';
                return;
            }

            if (d.type === 'count') {
                const cId = target === 'broadcast' ? 'live-count-broadcast' : `live-count-${target}`;
                const cEl = document.getElementById(cId);
                if (cEl) cEl.innerText = d.val;
                return;
            }

            const feedId = target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`;
            const feed = document.getElementById(feedId);

            if (d.type === 'chat') {
                if (d.msg.startsWith("BID:")) {
                    const amount = d.msg.split(":")[1];
                    updatePriceDisplay(amount, target, d.user);

                    const bidFeedId = target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`;
                    const bidFeed = document.getElementById(bidFeedId);
                    if (bidFeed) {
                        const div = document.createElement('div');
                        div.className = 'bid-bubble';
                        div.innerHTML = `<span class="bidder">${d.user}</span> ₺${amount}`;
                        bidFeed.appendChild(div);
                        bidFeed.scrollTop = bidFeed.scrollHeight;
                        setTimeout(() => {
                            div.classList.add('fade-out');
                            div.addEventListener('animationend', () => div.remove());
                        }, 10000);
                    }
                } else {
                    if (feed) {
                        const div = document.createElement('div');
                        div.className = 'msg';
                        div.innerHTML = `<b>${d.user}:</b> ${d.msg}`;
                        feed.appendChild(div);
                        feed.scrollTop = feed.scrollHeight;
                        setTimeout(() => {
                            div.classList.add('fade-out');
                            div.addEventListener('animationend', () => div.remove());
                        }, 8000);
                    }
                }
            }
        };
    }

    // --- YAYINCI (BROADCASTER) ---

    if (MODE === 'broadcast') {
        const prev = document.getElementById('preview');
        let rec;

        async function getDevices() {
            try {
                await navigator.mediaDevices.getUserMedia({ audio: true });
                const devices = await navigator.mediaDevices.enumerateDevices();
                const audioSelect = document.getElementById('audioSource');
                if (audioSelect) {
                    audioSelect.innerHTML = '';
                    const audioInputs = devices.filter(device => device.kind === 'audioinput');
                    audioInputs.forEach(device => {
                        const option = document.createElement('option');
                        option.value = device.deviceId;
                        option.text = device.label || `Mikrofon ${audioSelect.length + 1}`;
                        audioSelect.appendChild(option);
                    });
                }
            } catch (e) { console.error(e); }
        }

        async function initStream(audioDeviceId = null) {
            const constraints = {
                video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
                audio: audioDeviceId ? { deviceId: { exact: audioDeviceId } } : true
            };
            try {
                const stream = await navigator.mediaDevices.getUserMedia(constraints);
                window.localStream = stream;
                if (prev) {
                    prev.srcObject = stream;
                    prev.volume = 0;
                }
                if (!audioDeviceId) getDevices();
            } catch (err) {
                console.error(err);
                alert("Kamera/Mikrofon Hatası!");
            }
        }

        // Başlangıçta kamerayı aç
        initStream();

        window.restartStream = function () {
            const audioSelect = document.getElementById('audioSource');
            if (window.localStream) window.localStream.getTracks().forEach(t => t.stop());
            initStream(audioSelect.value);
        }

        window.startBroadcast = function () {
            document.getElementById('btn-start').style.display = 'none';
            document.getElementById('btn-stop').style.display = 'inline-block';

            connectChat('broadcast');

            const ws = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);

            ws.onopen = () => {
                let opts = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000, audioBitsPerSecond: 160000 };
                if (!MediaRecorder.isTypeSupported(opts.mimeType)) {
                    opts = { mimeType: 'video/webm', videoBitsPerSecond: 2500000, audioBitsPerSecond: 160000 };
                }

                rec = new MediaRecorder(window.localStream, opts);
                rec.start(500); // 1sn segment için 500ms chunk

                rec.ondataavailable = e => {
                    if (e.data.size > 0 && ws.readyState === 1) ws.send(e.data);
                };

                sendThumbnailSnapshot();
                window.thumbInterval = setInterval(sendThumbnailSnapshot, 60000);
            };

            window.stopBroadcast = function () {
                if (window.thumbInterval) clearInterval(window.thumbInterval);
                fetch('/broadcast/stop', { method: 'POST' });
                window.location.href = '/';
            };
        }

        // Modal Fonksiyonları
        window.openResetModal = function () {
            document.getElementById('resetModal').style.display = 'flex';
        }
        window.closeResetModal = function () {
            document.getElementById('resetModal').style.display = 'none';
        }
        window.confirmReset = function () {
            closeResetModal();
            fetch('/broadcast/reset_auction', { method: 'POST' });
        }

        window.toggleAuction = function () {
            AUCTION_ACTIVE = !AUCTION_ACTIVE;
            const btn = document.getElementById('btn-auction-toggle');
            const formData = new FormData();
            formData.append('active', AUCTION_ACTIVE);

            fetch('/broadcast/toggle_auction', { method: 'POST', body: formData });

            if (AUCTION_ACTIVE) {
                btn.innerText = "MEZATI KAPAT 🚫";
                btn.style.background = "rgba(255, 59, 48, 0.4)";
            } else {
                btn.innerText = "MEZAT AÇ 🔨";
                btn.style.background = "rgba(255, 255, 255, 0.2)";
            }
        }
    } else {
        // --- İZLEYİCİ (WATCHER) ---

        let obs = new IntersectionObserver((entries) => {
            entries.forEach(e => {
                const u = e.target.dataset.username;
                const v = document.getElementById(`video-${u}`);

                if (e.isIntersecting) {
                    const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`;

                    const attemptPlay = () => {
                        v.play().catch(error => {
                            console.log("Sesli engellendi, sessize alınıyor.");
                            v.muted = true;
                            v.play();
                            const hint = v.parentElement.querySelector('.tap-hint');
                            if (hint) hint.style.display = 'block';
                        });
                    };

                    if (Hls.isSupported()) {
                        const hlsConfig = {
                            enableWorker: true,
                            lowLatencyMode: true,
                            backBufferLength: 30,
                            liveSyncDurationCount: 3.5,
                            maxLiveSyncPlaybackRate: 1.2,
                        };
                        const h = new Hls(hlsConfig);
                        h.loadSource(src);
                        h.attachMedia(v);
                        h.on(Hls.Events.MANIFEST_PARSED, attemptPlay);
                    } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                        v.src = src;
                        attemptPlay();
                    }

                    connectChat(u);
                } else {
                    if (v) v.pause();
                }
            });
        }, { threshold: 0.6 });

        document.querySelectorAll('.stream-item').forEach(s => obs.observe(s));
    }

    // --- ETKİLEŞİM ---

    window.toggleFollow = function (username) {
        const btn = document.getElementById(`follow-btn-${username}`);
        const formData = new FormData();
        formData.append('username', username);

        fetch('/user/follow', { method: 'POST', body: formData })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'followed') {
                    btn.classList.add('following');
                    btn.innerText = 'Takip Ediliyor';
                } else {
                    btn.classList.remove('following');
                    btn.innerText = 'Takip Et';
                }
            });
    }

    window.sendBid = function (target, amount) {
        const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`;
        const el = document.getElementById(id);
        const currentVal = parseInt(el ? el.innerText.replace('.', '') : "0") || 0;
        const newVal = currentVal + amount;
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${newVal}`);
    }

    window.sendManualBid = function (target) {
        const inp = document.getElementById(`manual-bid-${target}`);
        const currentPriceEl = document.getElementById(target === 'broadcast' ? 'current-price-display' : `price-${target}`);
        let currentPrice = 0;
        if (currentPriceEl) {
            currentPrice = parseInt(currentPriceEl.innerText.replace(/\./g, '')) || 0;
        }

        if (inp && inp.value) {
            const offer = parseInt(inp.value);
            if (offer <= currentPrice) {
                inp.classList.add('error-shake');
                const oldVal = inp.value;
                inp.value = "";
                inp.placeholder = "Düşük!";
                setTimeout(() => {
                    inp.classList.remove('error-shake');
                    inp.placeholder = "Tutar";
                    inp.value = oldVal;
                }, 1000);
                return;
            }
            if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${inp.value}`);
            inp.value = "";
        }
    }

    window.sendMsg = function (target) {
        const inpId = target === 'broadcast' ? 'chat-input-broadcast' : `chat-input-${target}`;
        const inp = document.getElementById(inpId);
        if (inp && inp.value.trim()) {
            if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(inp.value);
            inp.value = "";
            inp.focus();
        }
    }

    async function sendThumbnailSnapshot() {
        const video = document.getElementById('preview');
        if (!video) return;

        const canvas = document.createElement('canvas');
        canvas.width = 640;
        canvas.height = 360;

        const ctx = canvas.getContext('2d');
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

        const dataUrl = canvas.toDataURL('image/jpeg', 0.6);

        try {
            await fetch('/broadcast/thumbnail', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ image: dataUrl, timestamp: Date.now() })
            });
            console.log("📸 Thumbnail güncellendi.");
        } catch (err) {
            console.error("Thumbnail hatası:", err);
        }
    }
});