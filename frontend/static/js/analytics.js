(function() {
    function generateUUID() {
        return "10000000-1000-4000-8000-100000000000".replace(/[018]/g, c =>
            (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
        );
    }

    const consent = localStorage.getItem('teqlif_cookie_consent');
    if (!consent && document.body) {
        showBanner();
    } else if (!consent) {
        document.addEventListener("DOMContentLoaded", showBanner);
    } else if (consent === 'accepted') {
        initTracking();
    }

    function showBanner() {
        if(document.querySelector('.cookie-banner')) return;
        const banner = document.createElement('div');
        banner.className = 'cookie-banner';
        banner.innerHTML = `
            <div class="cookie-content">
                <p><strong>teqlif</strong> deneyiminizi iyileştirmek, güvenlik sağlamak ve analiz yapmak için çerezler kullanıyoruz. <a href="/gizlilik-politikasi.html">Detaylı bilgi</a></p>
                <div class="cookie-actions">
                    <button id="btnRejectCookies" class="btn btn-outline" style="border-color:transparent;color:#94a3b8;background:transparent;box-shadow:none;">Sadece Zorunlu</button>
                    <button id="btnAcceptCookies" class="btn btn-primary">Tümünü Kabul Et</button>
                </div>
            </div>
        `;
        document.body.appendChild(banner);

        document.getElementById('btnAcceptCookies').onclick = function() {
            localStorage.setItem('teqlif_cookie_consent', 'accepted');
            banner.style.display = 'none';
            initTracking();
        };

        document.getElementById('btnRejectCookies').onclick = function() {
            localStorage.setItem('teqlif_cookie_consent', 'rejected');
            banner.style.display = 'none';
        };
    }

    function initTracking() {
        let sessionId = localStorage.getItem('teqlif_session_id');
        if (!sessionId) {
            sessionId = generateUUID();
            localStorage.setItem('teqlif_session_id', sessionId);
        }

        window.trackEvent = function(eventType, metadata = {}) {
            if (localStorage.getItem('teqlif_cookie_consent') !== 'accepted') return;
            
            const payload = {
                session_id: sessionId,
                event_type: eventType,
                url: window.location.href,
                device_type: /Mobile|Android|iP(ad|hone)/.test(navigator.userAgent) ? 'mobile' : 'desktop',
                os: getOS(),
                browser: getBrowser(),
                event_metadata: metadata
            };

            const token = localStorage.getItem('teqlif_token');
            const headers = { 'Content-Type': 'application/json' };
            if(token) headers['Authorization'] = `Bearer ${token}`;

            if (navigator.sendBeacon) {
                const blob = new Blob([JSON.stringify(payload)], { type: 'application/json' });
                navigator.sendBeacon('/api/analytics/track', blob);
            } else {
                fetch('/api/analytics/track', {
                    method: 'POST',
                    headers: headers,
                    body: JSON.stringify(payload),
                    keepalive: true
                }).catch(e => console.error(e));
            }
        };

        // Otomatik Sayfa Görüntüleme Track
        trackEvent('page_view', { title: document.title });

        // Tıklamaları İzle
        document.addEventListener('click', function(e) {
            const el = e.target.closest('button, a.btn, a[href]');
            if (!el) return;
            const action = el.innerText ? el.innerText.trim() : el.id || 'click';
            if (action) {
                trackEvent('click', { target: el.tagName, action: action, id: el.id, classes: el.className });
            }
        });
    }

    function getOS() {
        const ua = navigator.userAgent;
        if (ua.indexOf("Win") !== -1) return "Windows";
        if (ua.indexOf("Mac") !== -1) return "MacOS";
        if (ua.indexOf("Linux") !== -1) return "Linux";
        if (ua.indexOf("Android") !== -1) return "Android";
        if (ua.indexOf("like Mac") !== -1) return "iOS";
        return "Unknown";
    }

    function getBrowser() {
        const ua = navigator.userAgent;
        if (ua.indexOf("Firefox") > -1) return "Firefox";
        if (ua.indexOf("Opera") > -1 || ua.indexOf("OPR") > -1) return "Opera";
        if (ua.indexOf("Trident") > -1) return "IE";
        if (ua.indexOf("Edge") > -1) return "Edge";
        if (ua.indexOf("Chrome") > -1) return "Chrome";
        if (ua.indexOf("Safari") > -1) return "Safari";
        return "Unknown";
    }
})();
