// teqlif - Web Analytics Script (First-Party, Tamamen Özel)

(function () {
    const TRACKING_URL = '/api/analytics/track';
    
    // Rastgele Kullanıcı/Cihaz ID'si 
    let sessionId = localStorage.getItem('teqlif_session_id');
    const cookieConsent = localStorage.getItem('teqlif_cookie_consent');

    function generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
            var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    if (!sessionId) {
        sessionId = generateUUID();
        localStorage.setItem('teqlif_session_id', sessionId);
    }

    // --- UTM & Referrer Parsing ---
    function getUTMParams() {
        const params = new URLSearchParams(window.location.search);
        return {
            utm_source: params.get('utm_source') || null,
            utm_medium: params.get('utm_medium') || null,
            utm_campaign: params.get('utm_campaign') || null,
            referrer: document.referrer || null
        };
    }

    // --- Advanced Tracking Variables ---
    let pageStartTime = Date.now();
    let maxScrollDepth = 0;

    window.teqlifTrackEvent = function (eventType, metadata = {}) {
        if (localStorage.getItem('teqlif_cookie_consent') !== 'accepted') return;

        const payload = {
            session_id: sessionId,
            event_type: eventType,
            url: window.location.href,
            device_type: /Mobi|Android|iP(ad|hone)/i.test(navigator.userAgent) ? 'mobile' : 'desktop',
            os: getOS(),
            browser: getBrowser(),
            event_metadata: metadata
        };

        if (navigator.sendBeacon) {
            const blob = new Blob([JSON.stringify(payload)], { type: 'application/json' });
            navigator.sendBeacon(TRACKING_URL, blob);
        } else {
            fetch(TRACKING_URL, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
                keepalive: true
            }).catch(() => { });
        }
    };

    function getOS() {
        const ua = navigator.userAgent;
        if (ua.indexOf("Win") !== -1) return "Windows";
        if (ua.indexOf("Mac") !== -1) return "MacOS";
        if (ua.indexOf("Linux") !== -1) return "Linux";
        if (ua.indexOf("Android") !== -1) return "Android";
        if (ua.indexOf("like Mac") !== -1) return "iOS";
        return "Unknown OS";
    }

    function getBrowser() {
        const ua = navigator.userAgent;
        if (ua.indexOf("Firefox") > -1) return "Firefox";
        if (ua.indexOf("SamsungBrowser") > -1) return "Samsung Browser";
        if (ua.indexOf("Opera") > -1 || ua.indexOf("OPR") > -1) return "Opera";
        if (ua.indexOf("Trident") > -1) return "Internet Explorer";
        if (ua.indexOf("Edge") > -1) return "Edge";
        if (ua.indexOf("Chrome") > -1) return "Chrome";
        if (ua.indexOf("Safari") > -1) return "Safari";
        return "Unknown Browser";
    }

    function init() {
        if (localStorage.getItem('teqlif_cookie_consent') === 'accepted') {
            const utm = getUTMParams();
            teqlifTrackEvent('page_view', utm);

            // Eğer ilan sayfasındaysak "listing_view" event'ini tetikle
            const match = window.location.pathname.match(/\/ilan\/(\d+)/);
            if (match) {
                teqlifTrackEvent('listing_view', { listing_id: match[1] });
                initScrollTracking();
            }
        } else if (!cookieConsent) {
            showCookieBanner();
        }

        // Tıklamaları İzle (eski versiyondan devralındı)
        document.addEventListener('click', function(e) {
            const el = e.target.closest('button, a.btn, a[href]');
            if (!el) return;
            // Sadece tıklama takibi izni varsa
            if (localStorage.getItem('teqlif_cookie_consent') === 'accepted') {
                const action = el.innerText ? el.innerText.trim() : el.id || 'click';
                if (action) {
                    teqlifTrackEvent('click', { target: el.tagName, action: action, id: el.id, classes: el.className });
                }
            }
        });
    }

    // --- Scroll Depth Tracking ---
    function initScrollTracking() {
        window.addEventListener('scroll', () => {
            const scrollPercent = Math.round((window.scrollY + window.innerHeight) / document.documentElement.scrollHeight * 100);
            if (scrollPercent > maxScrollDepth) {
                maxScrollDepth = scrollPercent;
            }
        });
    }

    // --- Time Spent & Exit Tracking ---
    window.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') {
            const timeSpent = Math.round((Date.now() - pageStartTime) / 1000);
            if (timeSpent > 2) { 
                teqlifTrackEvent('time_spent', { seconds: timeSpent, max_scroll: maxScrollDepth });
            }
        } else if (document.visibilityState === 'visible') {
            pageStartTime = Date.now(); 
        }
    });

    // --- Search Tracking (Eğer arama kutusu varsa) ---
    document.addEventListener('submit', (e) => {
        if (e.target.tagName === 'FORM' && e.target.querySelector('input[type="search"]')) {
            const input = e.target.querySelector('input[type="search"]');
            if (input && input.value) {
                teqlifTrackEvent('search_query', { search_term: input.value });
            }
        }
    });

    function showCookieBanner() {
        const bannerStr = `
            <div id="teqlif-cookie-banner" class="cookie-banner">
                <div class="cookie-content">
                    <p>🍪 Deneyiminizi iyileştirmek, ilgilenmediğiniz ilanları filtrelemek ve size daha iyi hizmet verebilmek için <b>sadece kendi sunucularımızda</b> işlenen anonim çerezler kullanıyoruz. <a href="/gizlilik-politikasi" target="_blank">Detaylı Bilgi</a></p>
                    <div class="cookie-buttons">
                        <button id="cookie-reject" class="cookie-btn cookie-reject">Sadece Zorunlular</button>
                        <button id="cookie-accept" class="cookie-btn cookie-accept">Tümüne İzin Ver</button>
                    </div>
                </div>
            </div>`;
        document.body.insertAdjacentHTML('beforeend', bannerStr);

        document.getElementById('cookie-accept').addEventListener('click', () => {
            localStorage.setItem('teqlif_cookie_consent', 'accepted');
            document.getElementById('teqlif-cookie-banner').remove();
            init(); 
        });

        document.getElementById('cookie-reject').addEventListener('click', () => {
            localStorage.setItem('teqlif_cookie_consent', 'rejected');
            document.getElementById('teqlif-cookie-banner').remove();
        });
    }

    // Çalıştır
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
