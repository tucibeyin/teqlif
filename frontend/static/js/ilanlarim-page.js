    if (!Auth.getToken()) window.location.href = '/giris.html';

    const nav = document.getElementById('navHesabim');
    if (nav) nav.style.display = '';

    let _tab = new URLSearchParams(location.search).get('tab') || 'active';

    function fmt(p) {
        if (!p && p !== 0) return '';
        return '₺ ' + Number(p).toLocaleString('tr-TR', { minimumFractionDigits: 0 });
    }

    function switchTab(tab) {
        _tab = tab;
        history.replaceState(null, '', '?tab=' + tab);
        document.getElementById('tabActive').classList.toggle('active', tab === 'active');
        document.getElementById('tabPassive').classList.toggle('active', tab === 'passive');
        document.getElementById('pageTitle').textContent = tab === 'active' ? 'Aktif İlanlarım' : 'Pasif İlanlarım';
        load();
    }

    async function load() {
        document.getElementById('listContainer').innerHTML = '<div class="empty-state"><div>Yükleniyor...</div></div>';
        try {
            const activeParam = _tab === 'active' ? 'true' : 'false';
            const data = await apiFetch(`/listings/my?active=${activeParam}`);
            if (!data.length) {
                document.getElementById('listContainer').innerHTML = `
                    <div class="empty-state">
                        <div class="icon">${_tab === 'active' ? '📋' : '📦'}</div>
                        <div>${_tab === 'active' ? 'Aktif ilanınız yok.' : 'Pasif ilanınız yok.'}</div>
                    </div>`;
                return;
            }
            document.getElementById('listContainer').innerHTML = data.map(l => {
                const imgs = l.image_urls && l.image_urls.length ? l.image_urls : (l.image_url ? [l.image_url] : []);
                const thumb = imgs.length
                    ? `<div class="listing-thumb"><img src="${imgs[0]}" alt="" onerror="this.parentElement.innerHTML='📷'"></div>`
                    : `<div class="listing-thumb">📷</div>`;
                const isActive = l.is_active !== false;
                return `
                    <div class="listing-card" style="cursor:default;">
                        <a href="/ilan/${l.id}" style="display:contents;">
                            ${thumb}
                            <div class="listing-info">
                                <div class="listing-title">${esc(l.title)}</div>
                                <div class="listing-price">${fmt(l.price)}</div>
                            </div>
                        </a>
                        <div class="listing-actions">
                            <button class="action-btn ${isActive ? 'toggle-on' : 'toggle-off'}"
                                title="${isActive ? 'Pasife Al' : 'Aktif Yap'}"
                                onclick="toggleListing(${l.id}, this)">${isActive ? '👁' : '🙈'}</button>
                            <button class="action-btn danger"
                                title="Sil"
                                onclick="deleteListing(${l.id})">🗑</button>
                        </div>
                    </div>`;
            }).join('');
        } catch (e) {
            document.getElementById('listContainer').innerHTML = '<div class="empty-state"><div>Yüklenemedi.</div></div>';
        }
    }

    function esc(s) {
        return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    async function toggleListing(id, btn) {
        btn.disabled = true;
        try {
            const res = await apiFetch(`/listings/${id}/toggle`, { method: 'PATCH' });
            await load();
        } catch (_) { btn.disabled = false; }
    }

    async function deleteListing(id) {
        if (!confirm('Bu ilanı silmek istediğinize emin misiniz?')) return;
        try {
            await apiFetch(`/listings/${id}`, { method: 'DELETE' });
            await load();
        } catch (e) {
            alert(e.detail || 'Silme başarısız.');
        }
    }

    switchTab(_tab);

// ── Inline handler'lardan taşınan event listener'lar ─────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    var tabActive = document.getElementById('tabActive');
    if (tabActive) tabActive.addEventListener('click', function () { switchTab('active'); });
    var tabPassive = document.getElementById('tabPassive');
    if (tabPassive) tabPassive.addEventListener('click', function () { switchTab('passive'); });
});
