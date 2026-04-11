    if (!Auth.getToken()) window.location.href = '/giris.html';

    function fmt(p) {
        if (!p && p !== 0) return '';
        return '₺ ' + Number(p).toLocaleString('tr-TR', { minimumFractionDigits: 0 });
    }

    function esc(s) {
        return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    async function load() {
        document.getElementById('listContainer').innerHTML = '<div class="empty-state"><div>Yükleniyor...</div></div>';
        try {
            const data = await apiFetch('/favorites');
            if (!data.length) {
                document.getElementById('listContainer').innerHTML = `
                    <div class="empty-state">
                        <div class="icon">🤍</div>
                        <div>Henüz favori ilanınız yok.</div>
                        <div style="margin-top:.5rem;font-size:.85rem;">İlan detay sayfasından favorilere ekleyebilirsiniz.</div>
                    </div>`;
                return;
            }
            document.getElementById('listContainer').innerHTML = data.map(l => {
                const imgs = l.image_urls && l.image_urls.length ? l.image_urls : (l.image_url ? [l.image_url] : []);
                const thumb = imgs.length
                    ? `<div class="listing-thumb"><img src="${imgs[0]}" alt="" onerror="this.parentElement.innerHTML='📷'"></div>`
                    : `<div class="listing-thumb">📷</div>`;
                const seller = l.user ? `@${esc(l.user.username)}` : '';
                return `
                    <div class="listing-card">
                        <a href="/ilan/${l.id}" style="display:contents;">
                            ${thumb}
                            <div class="listing-info">
                                <div class="listing-title">${esc(l.title)}</div>
                                <div class="listing-price">${fmt(l.price)}</div>
                                ${seller ? `<div class="listing-seller">${seller}</div>` : ''}
                            </div>
                        </a>
                        <button class="unfav-btn" title="Favoriden Çıkar" onclick="removeFav(${l.id}, this)">❤</button>
                    </div>`;
            }).join('');
        } catch (e) {
            document.getElementById('listContainer').innerHTML = '<div class="empty-state"><div>Yüklenemedi.</div></div>';
        }
    }

    async function removeFav(id, btn) {
        btn.disabled = true;
        try {
            await apiFetch(`/favorites/${id}`, { method: 'DELETE' });
            await load();
        } catch (_) { btn.disabled = false; }
    }

    load();
