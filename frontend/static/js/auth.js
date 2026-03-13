const Auth = (() => {
    const TOKEN_KEY = 'teqlif_token';
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
        localStorage.setItem(USER_KEY, JSON.stringify(data.user));
    }

    function logout() {
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(USER_KEY);
        window.location.href = '/giris.html';
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

    return { getToken, getUser, login, register, verify, logout, me };
})();

// Nav'ı kullanıcı durumuna göre güncelle
(function updateNav() {
    const token = Auth.getToken();
    const user = Auth.getUser();
    const navLinks = document.querySelector('.nav-links');
    if (!navLinks) return;

    if (token && user) {
        navLinks.innerHTML = `
            <a href="/ilanlar.html">İlanlar</a>
            <a href="/ilan-ver.html">İlan Ver</a>
            <span style="padding:0.4rem 0.9rem;font-size:0.9rem;color:var(--text-muted);">
                @${user.username}
            </span>
            <a href="#" onclick="Auth.logout();return false;" class="btn-nav">Çıkış</a>
        `;
    } else if (token && !user) {
        // Bozuk oturum — temizle
        Auth.logout();
    }
})();
