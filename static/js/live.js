document.addEventListener('DOMContentLoaded', () => {
    // 1. AYARLAR
    const CONFIG = window.TEQLIF_CONFIG || {};
    const MODE = CONFIG.mode;
    // Güvenli bağlantı (wss://) veya normal (ws://) otomatik seçimi
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";

    window.CURRENT_SOCKET = null;
    let AUCTION_ACTIVE = CONFIG.auctionActive;
    let activeGiftTarget = null;

    // 2. YARDIMCI FONKSİYONLAR (Fiyat Güncelleme)
    function updatePriceDisplay(amount, target, bidderName) {
        const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`;
        const el = document.getElementById(id);
        if (el) {
            el.innerText = amount;
            // Yanıp sönme efekti için sınıfı kaldırıp tekrar ekle
            el.classList.remove("blink-anim");
            void el.offsetWidth;
            el.classList.add("blink-anim");
        }

        // Lider tablosunu güncelle
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

    // 3. SOCKET BAĞLANTISI (Chat, Sayac, Mezat)
    window.connectChat = function (target) {
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.close();

        // Oda ismi belirleme: Yayıncıysak kendi ismimiz, izleyiciysek hedef yayıncı
        let streamName = (target === 'broadcast') ? CONFIG.username : target;

        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/chat?stream=${streamName}`);
        window.CURRENT_SOCKET = ws;

        ws.onmessage = (e) => {
            const d = JSON.parse(e.data);

            // --- A. İZLEYİCİ SAYISI ---
            if (d.type === 'count') {
                const countId = (target === 'broadcast') ? 'live-count-broadcast' : `live-count-${target}`;
                const el = document.getElementById(countId);
                if (el) el.innerText = d.val;
                return;
            }

            // --- B. MEZAT DURUMU ---
            if (d.type === 'init') { updatePriceDisplay(d.price, target, d.leader); return; }

            if (d.type === 'auction_state') {
                const layer = document.getElementById(target === 'broadcast' ? '' : `bid-layer-${target}`);
                const board = document.getElementById(target === 'broadcast' ? '' : `price-board-${target}`);
                // Mezat açıksa göster, kapalıysa gizle
                if (layer) layer.style.display = d.active ? 'flex' : 'none';
                if (board) board.style.display = d.active ? 'flex' : 'none';
                return;
            }

            if (d.type === 'reset_auction') {
                updatePriceDisplay(0, target, null);
                const bidFeed = document.getElementById(target === 'broadcast' ? 'bid-feed-broadcast' : `bid-feed-${target}`);
                if (bidFeed) bidFeed.innerHTML = ''; // Teklif geçmişini temizle
                return;
            }

            // --- C. HEDİYE ---
            if (d.type === 'gift') { showGiftAnimation(d.gift_type, d.sender); return; }

            // --- D. MESAJLAR VE TEKLİFLER ---
            const feedId = target === 'broadcast' ? 'chat-feed-broadcast' : `chat-feed-${target}`;
            const feed = document.getElementById(feedId);

            if (d.type === 'chat') {
                // Eğer mesaj bir teklif ise (BID:100 gibi)
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
                        // Teklif balonunu 10 sn sonra sil
                        setTimeout(() => { div.remove(); }, 10000);
                    }
                } else {
                    // Normal Sohbet Mesajı
                    if (feed) {
                        const div = document.createElement('div');
                        // DİKKAT: 'fade-out' sınıfını hemen eklemiyoruz!
                        div.className = 'msg';
                        div.innerHTML = `<b>${d.user}:</b> ${d.msg}`;
                        feed.appendChild(div);
                        feed.scrollTop = feed.scrollHeight;

                        // 5 SANİYE BEKLE, SONRA SİL (DÜZELTME BURADA)
                        setTimeout(() => {
                            div.classList.add('fade-out'); // Animasyonu başlat
                            div.addEventListener('animationend', () => div.remove()); // Bitince yok et
                        }, 5000);
                    }
                }
            }
        };
    }

    // 4. HEDİYE SİSTEMİ
    window.openGiftMenu = function (username) { activeGiftTarget = username; document.getElementById('giftMenu').style.display = 'block'; }
    window.closeGiftMenu = function () { document.getElementById('giftMenu').style.display = 'none'; }

    window.sendGift = function (giftType) {
        if (!activeGiftTarget) return;
        const formData = new FormData();
        formData.append('target_username', activeGiftTarget);
        formData.append('gift_type', giftType);

        fetch('/gift/send', { method: 'POST', body: formData })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    // Bakiyeyi güncelle (hem ekrandaki hem menüdeki)
                    const sc = document.getElementById('screen-diamond-count');
                    const mc = document.getElementById('menu-diamond-count');
                    if (sc) sc.innerText = data.new_balance;
                    if (mc) mc.innerText = data.new_balance;
                    closeGiftMenu();
                } else { alert(data.msg); }
            });
    }

    function showGiftAnimation(giftType, senderName) {
        const layer = document.getElementById('gift-animation-layer');
        if (!layer) return;
        const emojis = { 'rose': '🌹', 'heart': '❤️', 'car': '🏎️', 'rocket': '🚀' };
        const emoji = emojis[giftType] || '🎁';

        const el = document.createElement('div');
        el.className = 'flying-gift';
        el.innerHTML = `${emoji}<div class="gift-sender-label">${senderName}</div>`;
        layer.appendChild(el);

        // 3 saniye sonra animasyon elementini sil
        setTimeout(() => { el.remove(); }, 3000);
    }

    // 5. YAYINCI KODLARI (BROADCAST MODE)
    if (MODE === 'broadcast') {
        const prev = document.getElementById('preview');
        let rec;

        // Kamerayı Başlat
        async function initStream() {
            try {
                const stream = await navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720 }, audio: true });
                window.localStream = stream;
                if (prev) { prev.srcObject = stream; prev.volume = 0; }

                // Mikrofonları listele
                const devices = await navigator.mediaDevices.enumerateDevices();
                const audioSelect = document.getElementById('audioSource');
                if (audioSelect) {
                    audioSelect.innerHTML = '';
                    devices.filter(d => d.kind === 'audioinput').forEach(d => {
                        const opt = document.createElement('option');
                        opt.value = d.deviceId;
                        opt.text = d.label || `Mikrofon ${audioSelect.length + 1}`;
                        audioSelect.appendChild(opt);
                    });
                }
            } catch (err) { console.error(err); alert("Kamera hatası! İzinleri kontrol edin."); }
        }
        initStream(); // Sayfa açılınca kamera önizlemesini başlat

        window.restartStream = function () {
            const audioSelect = document.getElementById('audioSource');
            if (window.localStream) window.localStream.getTracks().forEach(t => t.stop());
            // Seçili mikrofon ile yeniden başlat (Basitleştirildi)
            initStream();
        }

        // YAYINI BAŞLAT BUTONU
        const startBtn = document.getElementById('btn-start-broadcast');
        if (startBtn) {
            startBtn.addEventListener('click', function () {
                const title = document.getElementById('streamTitle').value;
                const category = document.getElementById('streamCategory').value;

                if (!title) { alert("Lütfen yayın başlığı girin!"); return; }

                const formData = new FormData();
                formData.append('title', title);
                formData.append('category', category);

                fetch('/broadcast/start', { method: 'POST', body: formData })
                    .then(res => res.json())
                    .then(data => {
                        // Setup ekranını gizle, Canlı arayüzü göster
                        document.getElementById('setup-layer').style.display = 'none';
                        document.getElementById('live-ui').style.display = 'flex';

                        // Kategori rozetini güncelle
                        if (document.getElementById('cat-badge-display'))
                            document.getElementById('cat-badge-display').innerText = category;

                        // Chat ve Veri bağlantısını kur
                        window.connectChat('broadcast');

                        // Yayın Socket'ini aç ve veri göndermeye başla
                        const ws = new WebSocket(`${protocol}://${window.location.host}/ws/broadcast`);
                        ws.onopen = () => {
                            let opts = { mimeType: 'video/webm;codecs=h264', videoBitsPerSecond: 2500000 };
                            if (!MediaRecorder.isTypeSupported(opts.mimeType)) opts = { mimeType: 'video/webm', videoBitsPerSecond: 2500000 };

                            rec = new MediaRecorder(window.localStream, opts);
                            rec.start(500); // 500ms'de bir veri gönder
                            rec.ondataavailable = e => { if (e.data.size > 0 && ws.readyState === 1) ws.send(e.data); };

                            sendThumbnailSnapshot();
                            window.thumbInterval = setInterval(sendThumbnailSnapshot, 60000); // 1 dakikada bir küçük resim
                        };
                    });
            });
        }

        window.stopBroadcast = function () {
            if (window.thumbInterval) clearInterval(window.thumbInterval);
            fetch('/broadcast/stop', { method: 'POST' });
            window.location.href = '/';
        };

        window.toggleAuction = function () {
            AUCTION_ACTIVE = !AUCTION_ACTIVE;
            const btn = document.getElementById('btn-auction-toggle');
            const formData = new FormData();
            formData.append('active', AUCTION_ACTIVE);

            fetch('/broadcast/toggle_auction', { method: 'POST', body: formData });

            if (AUCTION_ACTIVE) {
                btn.innerHTML = "🚫 Kapat";
                btn.style.background = "rgba(255, 59, 48, 0.4)";
            } else {
                btn.innerHTML = "🔨 Mezat";
                btn.style.background = "rgba(255, 255, 255, 0.2)";
            }
        }

        // Modallar
        window.openResetModal = function () { document.getElementById('resetModal').style.display = 'flex'; }
        window.closeResetModal = function () { document.getElementById('resetModal').style.display = 'none'; }
        window.confirmReset = function () { closeResetModal(); fetch('/broadcast/reset_auction', { method: 'POST' }); }

        // Küçük Resim Gönderimi
        async function sendThumbnailSnapshot() {
            const video = document.getElementById('preview');
            if (!video) return;
            const canvas = document.createElement('canvas');
            canvas.width = 640; canvas.height = 360;
            canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
            try {
                await fetch('/broadcast/thumbnail', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ image: canvas.toDataURL('image/jpeg', 0.6), timestamp: Date.now() })
                });
            } catch (err) { }
        }

    } else {
        // --- İZLEYİCİ MANTIĞI ---
        let obs = new IntersectionObserver((entries) => {
            entries.forEach(e => {
                const u = e.target.dataset.username;
                const v = document.getElementById(`video-${u}`);
                if (e.isIntersecting) {
                    const src = `/static/hls/${u}/master.m3u8?t=${Date.now()}`;
                    if (Hls.isSupported()) {
                        const h = new Hls(); h.loadSource(src); h.attachMedia(v);
                        h.on(Hls.Events.MANIFEST_PARSED, () => v.play().catch(() => { v.muted = true; v.play() }));
                    } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
                        v.src = src; v.play().catch(() => { v.muted = true; v.play() });
                    }
                    window.connectChat(u);
                } else { if (v) v.pause(); }
            });
        }, { threshold: 0.6 });
        document.querySelectorAll('.stream-item').forEach(s => obs.observe(s));
    }

    // --- ORTAK İŞLEMLER ---
    window.unmuteVideo = function (u) {
        const v = document.getElementById(`video-${u}`);
        if (v) { v.muted = false; v.volume = 1.0; v.parentElement.querySelector('.tap-hint').style.display = 'none'; }
    }

    window.toggleFollow = function (username) {
        const btn = document.getElementById(`follow-btn-${username}`);
        const formData = new FormData();
        formData.append('username', username);
        fetch('/user/follow', { method: 'POST', body: formData }).then(res => res.json()).then(data => {
            if (data.status === 'followed') {
                if (btn) { btn.classList.add('following'); btn.innerText = 'Takip'; }
            } else {
                if (btn) { btn.classList.remove('following'); btn.innerText = 'Takip Et'; }
            }
        });
    }

    window.sendBid = function (target, amount) {
        const id = target === 'broadcast' ? 'current-price-display' : `price-${target}`;
        const el = document.getElementById(id);
        const currentVal = parseInt(el ? el.innerText.replace('.', '') : "0") || 0;
        if (window.CURRENT_SOCKET) window.CURRENT_SOCKET.send(`BID:${currentVal + amount}`);
    }

    window.sendManualBid = function (target) {
        const inp = document.getElementById(`manual-bid-${target}`);
        if (inp && inp.value) { window.CURRENT_SOCKET.send(`BID:${inp.value}`); inp.value = ""; }
    }

    window.sendMsg = function (target) {
        const inpId = target === 'broadcast' ? 'chat-input-broadcast' : `chat-input-${target}`;
        const inp = document.getElementById(inpId);
        if (inp && inp.value.trim()) { window.CURRENT_SOCKET.send(inp.value); inp.value = ""; inp.focus(); }
    }
});