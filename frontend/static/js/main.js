const API = '/api';

async function apiFetch(path, options = {}) {
    const token = localStorage.getItem('teqlif_token');
    const headers = { 'Content-Type': 'application/json', ...options.headers };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const res = await fetch(API + path, { ...options, headers });
    if (!res.ok) throw await res.json();
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
