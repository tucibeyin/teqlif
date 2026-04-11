const Auth = (() => {
    // Token'lar artık HttpOnly cookie'de; XSS ile okunamaz.
    // Sadece user bilgisi (non-sensitive) localStorage'da tutulur.
    // In-memory token: sayfa yenilenmediği sürece WS auth için kullanılır.
    const USER_KEY = 'teqlif_user';
    let _memToken = null; // in-memory access token (WS için)

    // Eski localStorage token'larını tek seferlik temizle (migration)
    localStorage.removeItem('teqlif_token');
    localStorage.removeItem('teqlif_refresh');

    function getToken() {
        return _memToken;
    }

    function getUser() {
        try {
            const u = localStorage.getItem(USER_KEY);
            return u && u !== 'undefined' ? JSON.parse(u) : null;
        } catch (err) {
            console.warn('[Auth] getUser JSON parse hatası:', err);
            return null;
        }
    }

    function _save(data) {
        // Tokens → cookie (backend tarafından set edildi), buraya kaydetme
        _memToken = data.access_token || null;
        if (data.user) localStorage.setItem(USER_KEY, JSON.stringify(data.user));
    }

    async function logout() {
        _memToken = null;
        localStorage.removeItem(USER_KEY);
        // Backend cookie'yi temizler
        try {
            await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });
        } catch (_) {}
        window.location.href = '/giris.html';
    }

    async function tryRefresh() {
        try {
            // Cookie otomatik gider (credentials: 'include'), body gerekmez
            const res = await fetch('/api/auth/refresh', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({}),
            });
            if (!res.ok) { await logout(); return false; }
            let data;
            try { data = await res.json(); } catch (_) { await logout(); return false; }
            if (!data?.access_token) { await logout(); return false; }
            _memToken = data.access_token;
            return true;
        } catch (err) {
            console.error('[Auth] tryRefresh ağ hatası:', err);
            if (window.Sentry) Sentry.captureException(err);
            return false;
        }
    }

    async function login(email, password) {
        const data = await apiFetch('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ email, password }),
        });
        _save(data);
        return data;
    }

    async function register(payload) {
        return apiFetch('/auth/register', {
            method: 'POST',
            body: JSON.stringify(payload),
        });
    }

    async function verify(email, code) {
        const data = await apiFetch('/auth/verify', {
            method: 'POST',
            body: JSON.stringify({ email, code }),
        });
        _save(data);
        return data;
    }

    async function me() {
        return apiFetch('/auth/me');
    }

    return { getToken, getUser, login, register, verify, logout, tryRefresh, me };
})();

// ── Unread count helper ────────────────────────────────────────────────────────
async function getUnreadCount() {
    try {
        const [notifResult, msgResult] = await Promise.allSettled([
            fetch('/api/notifications/unread-count', {
                headers: { 'Authorization': 'Bearer ' + Auth.getToken() }
            }),
            fetch('/api/messages/unread-count', {
                headers: { 'Authorization': 'Bearer ' + Auth.getToken() }
            }),
        ]);
        let total = 0;
        if (notifResult.status === 'fulfilled' && notifResult.value.ok) {
            const d = await notifResult.value.json();
            total += (d.count || 0);
        }
        if (msgResult.status === 'fulfilled' && msgResult.value.ok) {
            const d = await msgResult.value.json();
            total += (d.count || 0);
        }
        return total;
    } catch (err) {
        console.warn('[Auth] getUnreadCount hatası:', err);
        return 0;
    }
}

function _updateNavBadge(count) {
    const badge = document.getElementById('navBadge');
    if (!badge) return;
    if (count > 0) {
        badge.textContent = count > 99 ? '99+' : String(count);
        badge.style.display = 'flex';
    } else {
        badge.style.display = 'none';
    }
}

// Nav'ı kullanıcı durumuna göre güncelle
(function updateNav() {
    const user = Auth.getUser();
    const navLinks = document.querySelector('.nav-links');
    if (!navLinks) return;

    if (user) {
        navLinks.innerHTML = `
            <a href="/kesfet.html" style="padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);text-decoration:none;display:inline-flex;align-items:center;gap:0.3rem;">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
                Keşfet
            </a>
            <a href="/mesajlar.html" style="padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);text-decoration:none;position:relative;">
                Mesajlar
                <span id="navBadge" style="display:none;position:absolute;top:-4px;right:-2px;background:red;color:white;border-radius:50%;min-width:14px;height:14px;font-size:9px;align-items:center;justify-content:center;padding:0 2px;line-height:14px;text-align:center;"></span>
            </a>
            <a href="/profil.html?u=${user.username}" style="padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);text-decoration:none;">
                @${user.username}
            </a>
            <a href="#" onclick="Auth.logout();return false;" class="btn-nav">çıkış</a>
        `;

        // Initial badge fetch
        getUnreadCount().then(_updateNavBadge);
        // Poll every 60 seconds
        setInterval(() => getUnreadCount().then(_updateNavBadge), 60000);
    }
})();
