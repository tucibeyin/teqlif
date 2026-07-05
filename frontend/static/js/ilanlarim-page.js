    if (!Auth.getUser()) window.location.href = '/giris.html';

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
                const rawThumb = imgs.length ? imgs[0] : null;
                const thumb = rawThumb
                    ? `<div class="listing-thumb"><img src="${rawThumb}" alt=""></div>`
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
                            <button class="action-btn ${isActive ? 'toggle-on' : 'toggle-off'} js-toggle"
                                title="${isActive ? 'Pasife Al' : 'Aktif Yap'}"
                                data-listing-id="${l.id}"
                                data-active="${isActive}">${isActive ? '👁' : '🙈'}</button>
                            <button class="action-btn danger js-delete"
                                title="Sil"
                                data-listing-id="${l.id}">🗑</button>
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

    async function toggleListing(id, isActive) {
        if (isActive) {
            // Aktif → Pasif: uyarı
            const ok = confirm('Aktif promosyon silinecek.\nTekrar aktif etmek için 10 TUCi gerekecek.\n\nPassife almak istiyor musunuz?');
            if (!ok) return;
        } else {
            // Pasif → Aktif: maliyet bilgisi çek
            let costData = null;
            try { costData = await apiFetch(`/listings/${id}/reactivation-cost`); } catch (_) {}
            const isPremium  = costData?.is_premium    ?? false;
            const remaining  = costData?.free_remaining ?? 0;
            const cost       = costData?.cost           ?? 10;
            const balance    = costData?.balance        ?? 0;
            const canAfford  = costData?.can_afford     ?? false;

            if (!canAfford) {
                alert(`Yetersiz bakiye. Devam etmek için TUCi yükleyin.\nBakiyeniz: ${balance} TUCi`);
                return;
            }

            let msg;
            if (isPremium && remaining > 0) {
                msg = `${remaining} ücretsiz hakkınız var. 1 hak kullanılacak.`;
            } else if (isPremium) {
                msg = `Bu ayki hakkınız doldu. ${cost} TUCi ödenecek.`;
            } else {
                msg = `${cost} TUCi ödenecek. Bakiyeniz: ${balance} TUCi.\nPRO'ya geçerek ayda 5 ücretsiz hak kazanın.`;
            }
            const ok = confirm(`İlanı Tekrar Yayınla\n\n${msg}`);
            if (!ok) return;
        }

        try {
            await apiFetch(`/listings/${id}/toggle`, { method: 'PATCH' });
            await load();
        } catch (e) {
            if (e.status === 402) {
                alert('Yetersiz bakiye. Devam etmek için TUCi yükleyin.');
            }
        }
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

// ── Event delegation ─────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    var tabActive = document.getElementById('tabActive');
    if (tabActive) tabActive.addEventListener('click', function () { switchTab('active'); });
    var tabPassive = document.getElementById('tabPassive');
    if (tabPassive) tabPassive.addEventListener('click', function () { switchTab('passive'); });

    document.addEventListener('click', function (e) {
        const toggleBtn = e.target.closest('.js-toggle');
        if (toggleBtn) {
            const id       = parseInt(toggleBtn.dataset.listingId, 10);
            const isActive = toggleBtn.dataset.active === 'true';
            toggleListing(id, isActive);
            return;
        }
        const deleteBtn = e.target.closest('.js-delete');
        if (deleteBtn) {
            const id = parseInt(deleteBtn.dataset.listingId, 10);
            deleteListing(id);
        }
    });
});
