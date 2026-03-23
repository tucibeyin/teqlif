const API = '/api';

async function apiFetch(path, options = {}) {
    const token = localStorage.getItem('teqlif_token');
    const headers = { 'Content-Type': 'application/json', ...options.headers };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    let res;
    try {
        res = await fetch(API + path, { ...options, headers });
    } catch (networkErr) {
        // VPS tamamen kapalı veya ağ erişimi yok
        console.error('[apiFetch] Ağ hatası:', networkErr);
        if (window.Sentry) Sentry.captureException(networkErr);
        throw {
            success: false,
            error: {
                code: 'NETWORK_ERROR',
                message: 'Sunucuya ulaşılamıyor. Lütfen internet bağlantınızı kontrol edin ve daha sonra tekrar deneyin.',
            },
        };
    }

    if (!res.ok) {
        const ct = res.headers.get('content-type') || '';
        if (!ct.includes('application/json')) {
            // Nginx 502/503/504 veya başka bir HTML hata sayfası
            console.error(`[apiFetch] Sunucu hatası (${res.status}) — JSON dışı yanıt`);
            if (window.Sentry) Sentry.captureMessage(`[apiFetch] HTTP ${res.status} non-JSON response: ${path}`, 'error');
            throw {
                success: false,
                error: {
                    code: 'SERVER_DOWN',
                    message: 'Sunucularımızda anlık bir bakım çalışması var. Lütfen birazdan tekrar deneyin.',
                },
            };
        }
        throw await res.json();
    }

    return res.json();
}

// Cloudflare Turnstile — invisible widget auto-render + global token cache
// Sayfa yüklenince widget otomatik çalışır, token burada saklanır.
let _cfToken = null;

window.onTurnstileToken = function (token) {
    _cfToken = token;
    console.log('[Turnstile] Token alındı ✓ | ilk 10 kar:', token.slice(0, 10) + '...');
};
window.onTurnstileError  = function (code)  {
    console.error('[Turnstile] Widget hatası — token üretilemedi | kod:', code);
    _cfToken = null;
};
window.onTurnstileExpire = function () {
    console.warn('[Turnstile] Token süresi doldu — widget yenileniyor');
    _cfToken = null;
};

// Submit anında çağrılır; token hazırsa anında döner, yoksa en fazla 10s bekler (fail-open).
async function getCaptchaToken() {
    console.log('[getCaptchaToken] Çağrıldı | _cfToken mevcut:', !!_cfToken,
                '| turnstile yüklü:', typeof turnstile !== 'undefined');

    // Token henüz üretilmediyse bekle (sayfa yeni yüklendi veya önceki token tüketildi)
    if (!_cfToken) {
        console.warn('[getCaptchaToken] Token yok — en fazla 10s bekleniyor...');
        await new Promise((resolve) => {
            const deadline = Date.now() + 10000;
            const poll = () => {
                if (_cfToken) { resolve(); return; }
                if (Date.now() >= deadline) {
                    console.error('[getCaptchaToken] 10s timeout doldu — fail-open ile devam');
                    resolve();
                    return;
                }
                setTimeout(poll, 200);
            };
            poll();
        });
    }

    const tok = _cfToken;
    _cfToken = null; // tek kullanımlık

    console.log('[getCaptchaToken] Dönen token:', tok ? tok.slice(0, 10) + '...' : 'NULL');

    // Sonraki işlem için hemen yeni token üretimini tetikle
    try {
        if (window.turnstile) {
            const container = document.querySelector('.cf-turnstile');
            if (container) {
                turnstile.reset(container);
                console.log('[getCaptchaToken] turnstile.reset() tetiklendi');
            } else {
                console.warn('[getCaptchaToken] .cf-turnstile container bulunamadı!');
            }
        } else {
            console.warn('[getCaptchaToken] window.turnstile tanımlı değil — SDK yüklenmemiş olabilir');
        }
    } catch (e) {
        console.error('[getCaptchaToken] Turnstile reset hatası:', e);
    }

    return tok || null;
}

// Analytics ve Cookie Consent Enjeksiyonu
document.addEventListener("DOMContentLoaded", () => {
    const cssPath = '/static/css/cookie.css';
    if (!document.querySelector(`link[href="${cssPath}"]`)) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = cssPath;
        document.head.appendChild(link);
    }

    const baseScriptPath = '/static/js/analytics.js';
    const scriptVersion = '?v=2';
    if (!document.querySelector(`script[src^="${baseScriptPath}"]`)) {
        const script = document.createElement('script');
        script.src = baseScriptPath + scriptVersion;
        document.body.appendChild(script);
    }
});
