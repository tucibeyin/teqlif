    if (!Auth.getToken()) window.location.href = '/giris.html';

    const myUser = Auth.getUser();
    let _currentOtherUserId = null;
    let _currentOtherUsername = null;

    // ── Tab switching ──────────────────────────────────────────────────────
    function switchTab(name) {
        document.querySelectorAll('.tab-btn').forEach(b => {
            b.classList.toggle('active', b.dataset.tab === name);
        });
        document.querySelectorAll('.tab-panel').forEach(p => {
            p.classList.toggle('active', p.id === 'panel-' + name);
        });
    }

    // ── List / Chat toggle ─────────────────────────────────────────────────
    function showList() {
        document.getElementById('listView').style.display = '';
        document.getElementById('chatView').style.display = 'none';
        _currentOtherUserId = null;
    }

    function showChat(userId, username, handle) {
        _currentOtherUserId = userId;
        _currentOtherUsername = username;
        document.getElementById('listView').style.display = 'none';
        document.getElementById('chatView').style.display = 'block';
        const titleEl = document.getElementById('chatTitle');
        if (handle) {
            titleEl.innerHTML = `<a href="/profil.html?u=${encodeURIComponent(handle)}" style="color:inherit;text-decoration:none;">${escHtml(username)}</a>`;
        } else {
            titleEl.textContent = username;
        }
        loadMessages(userId);
    }

    // ── Helpers ────────────────────────────────────────────────────────────
    function timeAgo(isoStr) {
        if (!isoStr) return '';
        try {
            const dt = new Date(isoStr);
            const diff = Math.floor((Date.now() - dt.getTime()) / 1000);
            if (diff < 60) return 'şimdi';
            if (diff < 3600) return Math.floor(diff / 60) + 'd önce';
            if (diff < 86400) return Math.floor(diff / 3600) + 's önce';
            return Math.floor(diff / 86400) + 'g önce';
        } catch { return ''; }
    }

    function timeLabel(isoStr) {
        if (!isoStr) return '';
        try {
            const dt = new Date(isoStr);
            const h = String(dt.getHours()).padStart(2, '0');
            const m = String(dt.getMinutes()).padStart(2, '0');
            return h + ':' + m;
        } catch { return ''; }
    }

    function notifIcon(type) {
        switch (type) {
            case 'message':
                return '<svg viewBox="0 0 24 24"><path d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/></svg>';
            case 'bid':
                return '<svg viewBox="0 0 24 24"><path d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3"/></svg>';
            default:
                return '<svg viewBox="0 0 24 24"><path d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/></svg>';
        }
    }

    // ── Load Conversations ─────────────────────────────────────────────────
    async function loadConversations() {
        try {
            const data = await apiFetch('/messages/conversations');
            document.getElementById('convLoading').style.display = 'none';
            if (!data || data.length === 0) {
                document.getElementById('convEmpty').style.display = '';
                return;
            }
            document.getElementById('convList').style.display = '';
            const convList = document.getElementById('convList');
            convList.innerHTML = '';
            data.forEach(conv => {
                const initial = (conv.full_name || conv.username || '?')[0].toUpperCase();
                const unreadBadge = conv.unread_count > 0
                    ? `<span class="unread-badge">${conv.unread_count}</span>`
                    : '';
                const item = document.createElement('div');
                item.className = 'conv-item';
                item.innerHTML = `
                    <div class="conv-avatar">${initial}</div>
                    <div class="conv-body">
                        <div class="conv-header">
                            <span class="conv-name">${escHtml(conv.full_name || conv.username)}</span>
                            <span class="conv-time">${timeAgo(conv.last_at)}</span>
                        </div>
                        <div class="conv-meta">
                            <span class="conv-last">${escHtml(conv.last_message || '')}</span>
                            ${unreadBadge}
                        </div>
                    </div>
                `;
                item.addEventListener('click', () => showChat(conv.user_id, conv.full_name || conv.username, conv.username));
                convList.appendChild(item);
            });
        } catch (e) {
            document.getElementById('convLoading').textContent = 'Yüklenemedi.';
        }
    }

    // ── Load Notifications ─────────────────────────────────────────────────
    async function loadNotifications() {
        try {
            const data = await apiFetch('/notifications/');
            document.getElementById('notifLoading').style.display = 'none';
            // Mark all as read
            apiFetch('/notifications/mark-all-read', { method: 'POST' }).catch(() => { });
            if (!data || data.length === 0) {
                document.getElementById('notifEmpty').style.display = '';
                return;
            }
            document.getElementById('notifList').style.display = '';
            const notifList = document.getElementById('notifList');
            notifList.innerHTML = '';
            data.forEach(n => {
                const item = document.createElement('div');
                item.className = 'notif-item' + (n.is_read ? '' : ' unread');
                item.innerHTML = `
                    <div class="notif-icon">${notifIcon(n.type)}</div>
                    <div class="notif-body">
                        <div class="notif-title">${escHtml(n.title)}</div>
                        ${n.body ? `<div class="notif-text">${escHtml(n.body)}</div>` : ''}
                        <div class="notif-time">${timeAgo(n.created_at)}</div>
                    </div>
                `;
                notifList.appendChild(item);
            });
        } catch (e) {
            document.getElementById('notifLoading').textContent = 'Yüklenemedi.';
        }
    }

    // ── Load Messages for chat ─────────────────────────────────────────────
    async function loadMessages(otherUserId) {
        const msgContainer = document.getElementById('chatMessages');
        msgContainer.innerHTML = '<div style="text-align:center;color:var(--text-muted);padding:2rem;">Yükleniyor...</div>';
        try {
            const data = await apiFetch(`/messages/${otherUserId}`);
            msgContainer.innerHTML = '';
            if (!data || data.length === 0) {
                msgContainer.innerHTML = '<div style="text-align:center;color:var(--text-muted);padding:2rem;">Henüz mesaj yok. İlk mesajı gönder!</div>';
                return;
            }
            const myId = myUser ? myUser.id : null;
            data.forEach(msg => {
                appendBubble(msg, myId);
            });
            scrollToBottom();
        } catch (e) {
            msgContainer.innerHTML = '<div style="text-align:center;color:var(--danger);padding:2rem;">Mesajlar yüklenemedi.</div>';
        }
    }

    function appendBubble(msg, myId) {
        const msgContainer = document.getElementById('chatMessages');
        const isMe = msg.sender_id === myId;
        const div = document.createElement('div');
        div.className = 'bubble ' + (isMe ? 'mine' : 'theirs');
        div.innerHTML = `
            ${escHtml(msg.content)}
            <div class="bubble-time">${timeLabel(msg.created_at)}</div>
        `;
        msgContainer.appendChild(div);
    }

    function scrollToBottom() {
        const c = document.getElementById('chatMessages');
        c.scrollTop = c.scrollHeight;
    }

    // ── Send message ───────────────────────────────────────────────────────
    async function sendMsg() {
        if (!_currentOtherUserId) return;
        const input = document.getElementById('chatInput');
        const text = input.value.trim();
        if (!text) return;
        input.value = '';
        input.style.height = '';
        try {
            const msg = await apiFetch('/messages/send', {
                method: 'POST',
                body: JSON.stringify({ receiver_id: _currentOtherUserId, content: text }),
            });
            const myId = myUser ? myUser.id : null;
            appendBubble(msg, myId);
            scrollToBottom();
        } catch (e) {
            alert('Mesaj gönderilemedi.');
        }
    }

    function handleKey(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMsg();
        }
    }

    function escHtml(str) {
        if (!str) return '';
        return str
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ── Init ───────────────────────────────────────────────────────────────
    loadConversations();
    loadNotifications();

    // Auto-open chat if URL has ?to_id=&to_name= (e.g. from profil.html)
    (function checkUrlParams() {
        const p = new URLSearchParams(window.location.search);
        const toId = parseInt(p.get('to_id'), 10);
        const toName = p.get('to_name') || '';
        const toHandle = p.get('to_handle') || '';
        if (toId && toName) {
            showChat(toId, toName, toHandle);
        }
    })();

// ── Inline handler'lardan taşınan event listener'lar ─────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    var tabMessages = document.getElementById('tabMessages');
    if (tabMessages) tabMessages.addEventListener('click', function () { switchTab('messages'); });
    var tabNotifications = document.getElementById('tabNotifications');
    if (tabNotifications) tabNotifications.addEventListener('click', function () { switchTab('notifications'); });

    var btnChatBack = document.getElementById('btnChatBack');
    if (btnChatBack) btnChatBack.addEventListener('click', showList);

    var chatTextarea = document.getElementById('chatTextarea');
    if (chatTextarea) chatTextarea.addEventListener('keydown', handleKey);

    var btnChatSend = document.getElementById('btnChatSend');
    if (btnChatSend) btnChatSend.addEventListener('click', sendMsg);
});
