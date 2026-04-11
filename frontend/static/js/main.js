const API = '/api';

async function apiFetch(path, options = {}, retried = false) {
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

    // 401 → refresh token ile bir kez yenile
    if (res.status === 401 && !retried && typeof Auth !== 'undefined') {
        const refreshed = await Auth.tryRefresh();
        if (refreshed) return apiFetch(path, options, true);
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

    // 204 No Content veya boş body — JSON parse etme
    if (res.status === 204 || res.headers.get('content-length') === '0') return null;
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

// Token hazır olana kadar en fazla 10s bekler; timeout'ta fail-open ile devam eder.
async function _pollForToken() {
    if (_cfToken) return;
    console.warn('[getCaptchaToken] Token yok — en fazla 10s bekleniyor...');
    await new Promise((resolve) => {
        const deadline = Date.now() + 10_000;
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

// Bir sonraki işlem için Turnstile widget'ını sıfırlar ve yeni token üretimini tetikler.
function _resetTurnstile() {
    try {
        if (!window.turnstile) {
            console.warn('[getCaptchaToken] window.turnstile tanımlı değil — SDK yüklenmemiş olabilir');
            return;
        }
        const container = document.querySelector('.cf-turnstile');
        if (container) {
            turnstile.reset(container);
            console.log('[getCaptchaToken] turnstile.reset() tetiklendi');
        } else {
            console.warn('[getCaptchaToken] .cf-turnstile container bulunamadı!');
        }
    } catch (e) {
        console.error('[getCaptchaToken] Turnstile reset hatası:', e);
    }
}

// Submit anında çağrılır; token hazırsa anında döner, yoksa en fazla 10s bekler (fail-open).
async function getCaptchaToken() {
    console.log('[getCaptchaToken] Çağrıldı | _cfToken mevcut:', !!_cfToken,
                '| turnstile yüklü:', typeof turnstile !== 'undefined');

    await _pollForToken();

    const tok = _cfToken;
    _cfToken = null; // tek kullanımlık

    console.log('[getCaptchaToken] Dönen token:', tok ? tok.slice(0, 10) + '...' : 'NULL');

    _resetTurnstile();
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

    initTeqlifTour();
});

// ── Onboarding Turu (Driver.js) ──────────────────────────────────────────────
function restartTeqlifTour() {
    localStorage.removeItem('teqlif_tour_seen');
    window.location.href = '/index.html';
}

function initTeqlifTour() {
    if (localStorage.getItem('teqlif_tour_seen')) return;

    const driverObj = window.driver.js.driver({
        showProgress: true,
        animate: true,
        overlayColor: 'rgba(0,0,0,0.65)',
        nextBtnText: 'İleri →',
        prevBtnText: '← Geri',
        doneBtnText: 'Başlayalım! 🚀',
        onDestroyed: () => {
            localStorage.setItem('teqlif_tour_seen', 'true');
        },
        steps: [
            {
                // Adım 1 — Genel hoşgeldin (element yok, ortada popover)
                popover: {
                    title: "Teqlif'e Hoş Geldin! 🎉",
                    description: "Burada canlı yayınlarla ürün alıp satabilir, açık artırmalara katılabilirsin. Sana etrafı gezdirmeme izin ver.",
                    side: 'over',
                    align: 'center',
                },
            },
            {
                // Adım 2 — Kategori / Tab filtreleri
                element: '.tab-pills',
                popover: {
                    title: 'Kategoriler',
                    description: 'Buradan ilgilendiğin kategorideki ürünleri ve ihaleleri hızlıca filtreleyebilirsin.',
                    side: 'bottom',
                    align: 'start',
                },
            },
            {
                // Adım 3 — İlanlar / Yayınlar akışı
                element: '#section-canli',
                popover: {
                    title: 'Keşfet',
                    description: 'Burada güncel ilanları görebilir, beğendiklerine çift tıklayarak favorilerine ekleyebilirsin.',
                    side: 'top',
                    align: 'center',
                },
            },
            {
                // Adım 4 — Canlı yayın butonu
                element: '#tab-canli',
                popover: {
                    title: 'Aksiyon Burada!',
                    description: 'Canlı mezatlara katılmak veya kendi ürününü canlı yayında satmak için buraya tıklayabilirsin.',
                    side: 'bottom',
                    align: 'start',
                },
            },
        ],
    });

    driverObj.drive();
}
