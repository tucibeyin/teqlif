/* chat.js — Real-time canlı yayın sohbeti (WebSocket) */

const Chat = (() => {
    let _ws = null;
    let _streamId = null;
    let _reconnecting = false;
    let _pingInterval = null;

    function connect(streamId) {
        _streamId = streamId;
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
                } else if (msg.type === 'history') {
                    (msg.messages || []).forEach(_appendMessage);
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

    function _appendMessage(msg) {
        const list = document.getElementById('chatMessages');
        if (!list) return;

        const el = document.createElement('div');
        el.className = 'chat-msg';
        el.innerHTML = `<span class="chat-username">@${_esc(msg.username)}</span> <span class="chat-content">${_esc(msg.content)}</span>`;
        list.appendChild(el);

        // En fazla 50 mesaj göster
        while (list.children.length > 50) {
            list.removeChild(list.firstChild);
        }

        // En alta kaydır
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
