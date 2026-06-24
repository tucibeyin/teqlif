// Auth guard — giriş yoksa yönlendir
if (!Auth.getToken()) {
    window.location.href = '/giris.html?next=' + encodeURIComponent(window.location.pathname);
}


function showToast(msg, color) {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.style.background = color || '#1f2937';
    t.style.display = 'block';
    setTimeout(() => { t.style.display = 'none'; }, 3500);
}

async function loadWallet() {
    try {
        const res = await fetch('/api/wallet/balance', {
            headers: { 'Authorization': 'Bearer ' + Auth.getToken() }
        });
        if (!res.ok) {
            if (res.status === 401) { window.location.href = '/giris.html'; return; }
            return;
        }
        const data = await res.json();
        document.getElementById('balance-display').textContent = data.balance + ' TUCi';
        renderHistory(data.transactions || []);
    } catch (e) {
        console.error('Cüzdan yüklenemedi', e);
    }
}

const _TYPE_LABELS = {
    airdrop:        'Hoş geldin hediyesi',
    spend_lead_gen: 'Sıcak Talep blast',
    spend_ai:       'Yapay Zeka fiyatlama',
    web_topup:      'Web yükleme',
};

function renderHistory(txns) {
    const container = document.getElementById('txn-container');
    if (!txns.length) {
        container.innerHTML = '<p style="color:#9ca3af;font-size:.875rem">Henüz işlem yok.</p>';
        return;
    }
    // innerHTML içinde dinamik veri — XSS riski yok (sayısal amount, label string)
    container.innerHTML = txns.map(t => {
        const pos   = t.amount > 0;
        const cls   = pos ? 'pos' : 'neg';
        const sign  = pos ? '+' : '';
        const label = _TYPE_LABELS[t.transaction_type] || t.transaction_type;
        const date  = new Date(t.created_at).toLocaleString('tr-TR', {
            day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
        });
        const icon  = pos ? '⬆️' : '⬇️';
        const bg    = pos ? '#ecfdf5' : '#fef2f2';
        return `<div class="txn-row">
            <div class="txn-icon" style="background:${bg}">${icon}</div>
            <div>
                <div class="txn-label">${label}</div>
                <div class="txn-date">${date}</div>
            </div>
            <div class="txn-amount ${cls}">${sign}${t.amount} TUCi</div>
        </div>`;
    }).join('');
}

async function doTopup() {
    const btn = document.getElementById('btn-topup');
    btn.disabled = true;
    btn.textContent = 'İşleniyor…';
    try {
        const res = await fetch('/api/wallet/topup-manual', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + Auth.getToken(),
            },
            body: JSON.stringify({ amount: selectedAmount }),
        });
        const data = await res.json();
        if (!res.ok) {
            showToast(data.detail || 'Bir hata oluştu.', '#dc2626');
            return;
        }
        document.getElementById('balance-display').textContent = data.balance + ' TUCi';
        showToast(`✅ ${selectedAmount} TUCi başarıyla yüklendi!`, '#059669');
        await loadWallet();
    } catch (e) {
        showToast('Bağlantı hatası.', '#dc2626');
    } finally {
        btn.disabled = false;
        btn.textContent = '💳 Öde ve Yükle';
    }
}

loadWallet();
