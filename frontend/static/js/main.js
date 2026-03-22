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

    const scriptPath = '/static/js/analytics.js';
    if (!document.querySelector(`script[src="${scriptPath}"]`)) {
        const script = document.createElement('script');
        script.src = scriptPath;
        document.body.appendChild(script);
    }
});
