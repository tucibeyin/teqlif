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

    function connect(streamId, { onStreamEnded, onViewerCount, onMuted, onKicked, onUnmuted, onUsernameTap } = {}) {
        _streamId = streamId;
        _onStreamEnded = onStreamEnded || null;
        _onViewerCount = onViewerCount || null;
        _onMuted = onMuted || null;
        _onKicked = onKicked || null;
        _onUnmuted = onUnmuted || null;
        _onUsernameTap = onUsernameTap || null;
        _connectWS();
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

    function _appendMessage(msg) {
        const list = document.getElementById('chatMessages');
        if (!list) return;

        const color = _usernameColor(msg.username || '');
        const el = document.createElement('div');
        el.className = 'chat-msg';
        let html = `<span class="chat-username" data-username="${_esc(msg.username)}" style="color:${color};cursor:pointer;">@${_esc(msg.username)}</span> <span class="chat-content">${_esc(msg.content)}</span>`;
        if (msg.url) {
            html += ` <a href="${_esc(msg.url)}" target="_blank" style="color:#fbbf24;font-weight:600;text-decoration:underline;white-space:nowrap;">🔗 İlana Bak</a>`;
        }
        el.innerHTML = html;
        if (_onUsernameTap) {
            const usernameSpan = el.querySelector('.chat-username');
            if (usernameSpan) {
                usernameSpan.addEventListener('click', () => _onUsernameTap(msg.username));
            }
        }
        list.appendChild(el);

        // En fazla 50 mesaj göster
        while (list.children.length > 50) {
            list.removeChild(list.firstChild);
        }

        // En alta kaydır
        list.scrollTop = list.scrollHeight;
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

    return { connect, sendMessage, disconnect };
})();
