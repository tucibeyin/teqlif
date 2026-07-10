// Cached promise for the /auth/init response — shared across Auth and updateNav.
// Populated on first authenticated page load; reused by Auth.me() and updateNav().
let _initCtxPromise = null;

const Auth = (() => {
    // Access token artık yalnızca bellekte (_memToken) tutulur — localStorage/sessionStorage'a yazılmaz.
    // XSS bu değişkeni okuyamaz. Sayfa yenilenince Auth.ready promise'i üzerinden restore edilir.
    const USER_KEY     = 'teqlif_user';
    const _TOKEN_KEY   = 'teqlif_token';    // eski key — temizlik için tutuldu
    const _REFRESH_KEY = 'teqlif_refresh';  // eski key — temizlik için tutuldu
    const _SS_TOKEN    = 'teqlif_ss_token'; // eski key — temizlik için tutuldu

    // Migration: eski depolamadan bir kerelik oku, hemen sil.
    // Sonraki sayfa yüklemelerinde _memToken null olur; Auth.ready tryRefresh ile restore eder.
    let _memToken = (() => {
        const ss = sessionStorage.getItem(_SS_TOKEN);
        const ls = localStorage.getItem(_TOKEN_KEY);
        sessionStorage.removeItem(_SS_TOKEN);
        localStorage.removeItem(_TOKEN_KEY);
        localStorage.removeItem(_REFRESH_KEY);
        const t = (ss && ss !== 'undefined') ? ss : (ls && ls !== 'undefined' ? ls : null);
        return t;
    })();

    function getToken() {
        return _memToken;
    }

    const _USER_TTL_MS = 24 * 60 * 60 * 1000; // 24 saat

    function saveUser(user) {
        try { localStorage.setItem(USER_KEY, JSON.stringify({ _d: Date.now(), u: user })); } catch (_) {}
    }

    function getUser() {
        try {
            const raw = localStorage.getItem(USER_KEY);
            if (!raw || raw === 'undefined') return null;
            const parsed = JSON.parse(raw);
            // Eski format (TTL sarması olmayan düz obje) — geçerliyse döndür, sil
            if (!parsed._d) return parsed;
            if (Date.now() - parsed._d > _USER_TTL_MS) {
                localStorage.removeItem(USER_KEY);
                return null;
            }
            return parsed.u;
        } catch (err) {
            console.warn('[Auth] getUser JSON parse hatası:', err);
            return null;
        }
    }

    function _save(data) {
        _memToken = data.access_token || null;
        if (data.user) saveUser(data.user);
    }

    async function logout() {
        _memToken = null;
        localStorage.removeItem(USER_KEY);
        // Eski depolama anahtarlarını temizle
        localStorage.removeItem(_TOKEN_KEY);
        localStorage.removeItem(_REFRESH_KEY);
        sessionStorage.removeItem(_SS_TOKEN);
        try {
            await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });
        } catch (_) {}
        window.location.href = '/giris.html';
    }

    async function tryRefresh() {
        try {
            const res = await fetch('/api/auth/refresh', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({}),
            });
            if (!res.ok) { return false; }
            let data;
            try { data = await res.json(); } catch (_) { return false; }
            if (!data?.access_token) { return false; }
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
            body: JSON.stringify({ login_identifier: email, password }),
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

    async function forgotPassword(email) {
        const lang = (navigator.language || 'tr').split('-')[0];
        return apiFetch('/auth/forgot-password', {
            method: 'POST',
            body: JSON.stringify({ email, lang }),
        });
    }

    async function resetPassword(email, code, newPassword) {
        return apiFetch('/auth/reset-password', {
            method: 'POST',
            body: JSON.stringify({ email, code, new_password: newPassword }),
        });
    }

    async function me() {
        // Reuse the cached init context if available — avoids a redundant /auth/me call.
        if (_initCtxPromise) {
            const ctx = await _initCtxPromise.catch(() => null);
            if (ctx && ctx.user) return ctx.user;
        }
        return apiFetch('/auth/me');
    }

    function getInitContext() {
        if (!getUser()) return Promise.resolve(null);
        if (!_initCtxPromise) {
            _initCtxPromise = apiFetch('/auth/init').catch(() => null);
        }
        return _initCtxPromise;
    }

    return { getToken, getUser, saveUser, login, register, verify, forgotPassword, resetPassword, logout, tryRefresh, me, getInitContext };
})();

// Sayfa yüklenince token bellekte yoksa HttpOnly cookie üzerinden restore et.
// WS bağlantıları ve auth gerektiren işlemler Auth.ready'yi await ederek token'ın
// hazır olmasını bekler.
Auth.ready = (() => {
    if (Auth.getToken()) return Promise.resolve(true);
    if (!Auth.getUser())  return Promise.resolve(false);
    return Auth.tryRefresh();
})();

// ── Unread count helper ────────────────────────────────────────────────────────
async function getUnreadCount() {
    try {
        const [notifResult, msgResult] = await Promise.allSettled([
            apiFetch('/notifications/unread-count'),
            apiFetch('/messages/unread-count'),
        ]);
        let total = 0;
        if (notifResult.status === 'fulfilled' && notifResult.value) {
            total += (notifResult.value.count || 0);
        }
        if (msgResult.status === 'fulfilled' && msgResult.value) {
            total += (msgResult.value.count || 0);
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

// Nav'ı kullanıcı durumuna göre güncelle — DOM hazır olunca çalışır
function updateNav() {
    const user = Auth.getUser();
    const navLinks = document.querySelector('.nav-links');
    if (!navLinks) return;

    if (user) {
        // onclick yerine addEventListener — CSP unsafe-inline olmadan çalışır
        const kesfetA = document.createElement('a');
        kesfetA.href = '/kesfet.html';
        kesfetA.style.cssText = 'padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);text-decoration:none;display:inline-flex;align-items:center;gap:0.3rem;';
        kesfetA.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg> Keşfet';

        const walletA = document.createElement('a');
        walletA.href = '/user_panel.html';
        walletA.title = 'TUCi Cüzdanım';
        walletA.style.cssText = 'display:inline-flex;align-items:center;gap:0.35rem;padding:0.35rem 0.85rem;font-size:0.85rem;font-weight:700;color:#92400e;background:#fffbeb;border:1.5px solid #fbbf24;border-radius:20px;text-decoration:none;transition:background .15s,box-shadow .15s;white-space:nowrap;';
        walletA.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12V8a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-4"/><path d="M20 12h-5a2 2 0 0 0 0 4h5"/></svg><span id="navWalletLabel">Cüzdan</span>';
        walletA.addEventListener('mouseenter', () => { walletA.style.background = '#fef3c7'; walletA.style.boxShadow = '0 2px 8px rgba(251,191,36,.35)'; });
        walletA.addEventListener('mouseleave', () => { walletA.style.background = '#fffbeb'; walletA.style.boxShadow = ''; });

        const mesajlarA = document.createElement('a');
        mesajlarA.href = '/mesajlar.html';
        mesajlarA.style.cssText = 'padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);text-decoration:none;position:relative;';
        mesajlarA.textContent = 'Mesajlar';
        const badge = document.createElement('span');
        badge.id = 'navBadge';
        badge.style.cssText = 'display:none;position:absolute;top:-4px;right:-2px;background:red;color:white;border-radius:50%;min-width:14px;height:14px;font-size:9px;align-items:center;justify-content:center;padding:0 2px;line-height:14px;text-align:center;';
        mesajlarA.appendChild(badge);

        const profilA = document.createElement('a');
        profilA.href = `/profil.html?u=${user.username}`;
        profilA.style.cssText = 'padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);text-decoration:none;';
        profilA.textContent = `@${user.username}`;

        const cikisA = document.createElement('a');
        cikisA.href = '#';
        cikisA.className = 'btn-nav';
        cikisA.textContent = 'çıkış';
        cikisA.addEventListener('click', (e) => { e.preventDefault(); Auth.logout(); });

        navLinks.innerHTML = '';
        navLinks.append(kesfetA, walletA, mesajlarA, profilA, cikisA);

        // Single /auth/init call provides wallet + unread counts — no separate fetches needed.
        Auth.getInitContext().then(ctx => {
            if (!ctx) return;
            const lbl = document.getElementById('navWalletLabel');
            if (lbl && ctx.wallet_balance != null) lbl.textContent = `Cüzdan · ${ctx.wallet_balance} T`;
            _updateNavBadge((ctx.notifications_unread || 0) + (ctx.messages_unread || 0));
            if (ctx.user) localStorage.setItem('teqlif_user', JSON.stringify(ctx.user));
        }).catch(() => {});

        // Refresh unread count every 60s (only 2 lightweight calls, not on page load).
        setInterval(() => getUnreadCount().then(_updateNavBadge), 60000);
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', updateNav);
} else {
    updateNav();
}
