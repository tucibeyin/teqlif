const Auth = (() => {
    const TOKEN_KEY = 'teqlif_token';
    const REFRESH_KEY = 'teqlif_refresh';
    const USER_KEY = 'teqlif_user';

    function getToken() {
        const t = localStorage.getItem(TOKEN_KEY);
        return t && t !== 'undefined' ? t : null;
    }

    function getUser() {
        try {
            const u = localStorage.getItem(USER_KEY);
            return u && u !== 'undefined' ? JSON.parse(u) : null;
        } catch {
            return null;
        }
    }

    function _save(data) {
        localStorage.setItem(TOKEN_KEY, data.access_token);
        if (data.refresh_token) localStorage.setItem(REFRESH_KEY, data.refresh_token);
        if (data.user) localStorage.setItem(USER_KEY, JSON.stringify(data.user));
    }

    function logout() {
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(REFRESH_KEY);
        localStorage.removeItem(USER_KEY);
        window.location.href = '/giris.html';
    }

    async function tryRefresh() {
        const rt = localStorage.getItem(REFRESH_KEY);
        if (!rt) return false;
        try {
            const res = await fetch('/api/auth/refresh', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ refresh_token: rt }),
            });
            if (!res.ok) { logout(); return false; }
            const data = await res.json();
            localStorage.setItem(TOKEN_KEY, data.access_token);
            localStorage.setItem(REFRESH_KEY, data.refresh_token);
            return true;
        } catch {
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
    } catch {
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
    const token = Auth.getToken();
    const user = Auth.getUser();
    const navLinks = document.querySelector('.nav-links');
    if (!navLinks) return;

    if (token && user) {
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
    } else if (token && !user) {
        // Bozuk oturum — temizle
        Auth.logout();
    }
})();
