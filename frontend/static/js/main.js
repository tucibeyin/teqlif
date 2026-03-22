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
