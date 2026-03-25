/* chat.js — Real-time canlı yayın sohbeti (WebSocket) */

const Chat = (() => {
    let _ws = null;
    let _streamId = null;
    let _reconnecting = false;
    let _pingInterval = null;
    let _onStreamEnded = null;
    let _onViewerCount = null;
    let _onMuted = null;
    let _onKicked = null;
    let _onUnmuted = null;
    let _onUsernameTap = null;
    let _onModPromoted = null;
    let _onModDemoted  = null;

    function connect(streamId, { onStreamEnded, onViewerCount, onMuted, onKicked, onUnmuted, onUsernameTap, onModPromoted, onModDemoted } = {}) {
        _streamId = streamId;
        _onStreamEnded = onStreamEnded || null;
        _onViewerCount = onViewerCount || null;
        _onMuted = onMuted || null;
        _onKicked = onKicked || null;
        _onUnmuted = onUnmuted || null;
        _onUsernameTap = onUsernameTap || null;
        _onModPromoted = onModPromoted || null;
        _onModDemoted  = onModDemoted  || null;
        _connectWS();
    }

    function setUsernameTap(fn) {
        _onUsernameTap = fn || null;
    }

    function _connectWS() {
        const token = Auth.getToken();
        if (!token || !_streamId) return;

        const proto = location.protocol === 'https:' ? 'wss' : 'ws';
        const url = `${proto}://${location.host}/api/chat/${_streamId}/ws?token=${encodeURIComponent(token)}`;

        try {
            _ws = new WebSocket(url);
        } catch (_) {
            _scheduleReconnect();
            return;
        }

        _ws.onopen = () => {
            _reconnecting = false;
            clearInterval(_pingInterval);
            _pingInterval = setInterval(() => {
                if (_ws && _ws.readyState === WebSocket.OPEN) {
                    try { _ws.send('ping'); } catch (_) {}
                }
            }, 25000);
        };

        _ws.onmessage = (e) => {
            try {
                const msg = JSON.parse(e.data);
                if (msg.type === 'message') {
                    _appendMessage(msg);
                } else if (msg.type === 'system_join') {
                    _appendSystemJoin(msg.username);
                } else if (msg.type === 'history') {
                    (msg.messages || []).forEach(_appendMessage);
                } else if (msg.type === 'viewer_count') {
                    if (_onViewerCount) _onViewerCount(msg.count);
                } else if (msg.type === 'stream_ended') {
                    _streamId = null; // yeniden bağlanmayı engelle
                    if (_onStreamEnded) _onStreamEnded();
                } else if (msg.type === 'muted') {
                    if (_onMuted) _onMuted();
                } else if (msg.type === 'kicked') {
                    _streamId = null; // yeniden bağlanmayı engelle
                    if (_onKicked) _onKicked();
                } else if (msg.type === 'unmuted') {
                    if (_onUnmuted) _onUnmuted();
                } else if (msg.type === 'mod_promoted') {
                    if (_onModPromoted) _onModPromoted(msg);
                } else if (msg.type === 'mod_demoted') {
                    if (_onModDemoted) _onModDemoted(msg);
                }
            } catch (_) {}
        };

        _ws.onclose = () => {
            clearInterval(_pingInterval);
            _scheduleReconnect();
        };

        _ws.onerror = () => {
            try { _ws.close(); } catch (_) {}
        };
    }

    function _scheduleReconnect() {
        if (_reconnecting || !_streamId) return;
        _reconnecting = true;
        setTimeout(() => {
            if (!_streamId) return;
            _reconnecting = false;
            _connectWS();
        }, 4000);
    }

    const _PALETTE = [
        '#f87171', '#fb923c', '#fbbf24', '#a3e635',
        '#4ade80', '#2dd4bf', '#22d3ee', '#38bdf8',
        '#818cf8', '#c084fc', '#f472b6', '#fb7185',
    ];

    function _usernameColor(username) {
        let hash = 0;
        for (let i = 0; i < username.length; i++) {
            hash = (hash * 31 + username.charCodeAt(i)) & 0x7fffffff;
        }
        return _PALETTE[hash % _PALETTE.length];
    }

    function _buildAvatarEl(username, imageUrl) {
        const color = _usernameColor(username || '');
        const initial = username ? username[0].toUpperCase() : '?';

        function makeFallback() {
            const span = document.createElement('span');
            span.className = 'chat-avatar-fallback';
            span.style.background = color;
            span.setAttribute('aria-hidden', 'true');
            span.textContent = initial;
            return span;
        }

        if (imageUrl) {
            const img = document.createElement('img');
            img.className = 'chat-avatar';
            img.src = imageUrl;
            img.alt = '';
            img.setAttribute('aria-hidden', 'true');
            img.setAttribute('loading', 'lazy');
            img.onerror = function () { this.replaceWith(makeFallback()); };
            return img;
        }

        return makeFallback();
    }

    function _appendMessage(msg) {
        const list = document.getElementById('chatMessages');
        if (!list) return;

        const color = _usernameColor(msg.username || '');
        const el = document.createElement('div');
        el.className = msg.is_auction_result ? 'chat-msg chat-msg--auction-winner' : 'chat-msg';

        // Avatar — DOM element, onerror HTML string trick yok
        el.appendChild(_buildAvatarEl(msg.username || '', msg.profile_image_url || null));

        // Moderatör rozeti
        if (msg.is_mod) {
            const badge = document.createElement('span');
            badge.className = 'chat-badge chat-badge--mod';
            badge.textContent = '🛡 MOD';
            el.appendChild(badge);
        }
        // Host rozeti
        if (msg.is_host) {
            const badge = document.createElement('span');
            badge.className = 'chat-badge chat-badge--host';
            badge.textContent = '⚡ HOST';
            el.appendChild(badge);
        }

        // Kullanıcı adı
        const usernameSpan = document.createElement('span');
        usernameSpan.className = 'chat-username';
        usernameSpan.dataset.username = msg.username || '';
        usernameSpan.style.color = color;
        usernameSpan.textContent = '@' + (msg.username || '');
        if (_onUsernameTap) {
            usernameSpan.addEventListener('click', () => _onUsernameTap(msg.username));
        }
        el.appendChild(usernameSpan);
        el.appendChild(document.createTextNode(' '));

        // Mesaj içeriği
        const contentSpan = document.createElement('span');
        contentSpan.className = 'chat-content';
        contentSpan.textContent = msg.content || '';
        el.appendChild(contentSpan);

        // Opsiyonel ilan linki
        if (msg.url) {
            el.appendChild(document.createTextNode(' '));
            const link = document.createElement('a');
            link.href = msg.url;
            link.target = '_blank';
            link.style.cssText = 'color:#fbbf24;font-weight:600;text-decoration:underline;white-space:nowrap;';
            link.textContent = '🔗 İlana Bak';
            el.appendChild(link);
        }

        list.appendChild(el);

        // En fazla 50 mesaj göster
        while (list.children.length > 50) {
            list.removeChild(list.firstChild);
        }

        // Kullanıcı alta yakınsa auto-scroll; yukarı scroll ediyorsa dokunma
        const distFromBottom = list.scrollHeight - list.scrollTop - list.clientHeight;
        if (distFromBottom < 60) {
            list.scrollTop = list.scrollHeight;
        }
    }

    function _appendSystemJoin(username) {
        const list = document.getElementById('chatMessages');
        if (!list) return;
        const color = _usernameColor(username || '');
        const el = document.createElement('div');
        el.className = 'chat-msg';
        el.innerHTML = `<span class="chat-username" data-username="${_esc(username)}" style="color:${color};cursor:pointer;">@${_esc(username)}</span> <span class="chat-content" style="opacity:0.6;font-style:italic;">yayına katıldı</span>`;
        if (_onUsernameTap) {
            const usernameSpan = el.querySelector('.chat-username');
            if (usernameSpan) {
                usernameSpan.addEventListener('click', () => _onUsernameTap(username));
            }
        }
        list.appendChild(el);
        while (list.children.length > 50) list.removeChild(list.firstChild);
        list.scrollTop = list.scrollHeight;
    }

    function _esc(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function sendMessage(content) {
        if (!content || !_ws || _ws.readyState !== WebSocket.OPEN) return;
        try {
            _ws.send(JSON.stringify({ type: 'message', content }));
        } catch (_) {}
    }

    function disconnect() {
        _streamId = null;
        clearInterval(_pingInterval);
        if (_ws) { try { _ws.close(); } catch (_) {} _ws = null; }
    }

    return { connect, sendMessage, disconnect, setUsernameTap };

})();
