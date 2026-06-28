const GOOGLE_CLIENT_ID = "232766108005-c193qv63qkv5c6m3c2klrs2ihoj7b2ok.apps.googleusercontent.com";
let currentUserId = null;

window.onload = function () {
    if (sessionStorage.getItem("teqlif_admin_session")) { showFinalStep(); } else { initGoogleAuth(); }
};

function getAuthHeaders() {
    return { 'Content-Type': 'application/json', 'Authorization': `Bearer ${sessionStorage.getItem("teqlif_admin_session")}` };
}

// ── AUTH ──────────────────────────────────────────────────────────────────────
function initGoogleAuth() {
    google.accounts.id.initialize({ client_id: GOOGLE_CLIENT_ID, callback: handleCredentialResponse });
    google.accounts.id.renderButton(document.getElementById("buttonDiv"), { theme: "outline", size: "large", width: "100%" });
}
async function handleCredentialResponse(r) {
    const res = await fetch('/api/admin-auth/verify-google', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: r.credential }) });
    if (res.ok) { document.getElementById("step-google").classList.add("hidden"); document.getElementById("step-password").classList.remove("hidden"); }
    else { alert("Erişim reddedildi."); }
}
async function verifyPassword() {
    const p = document.getElementById("adminPasswordInput").value;
    const res = await fetch('/api/admin-auth/verify-password', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: p }) });
    if (res.ok) { const data = await res.json(); sessionStorage.setItem("teqlif_admin_session", data.access_token); showFinalStep(); }
    else { alert("Hatalı şifre!"); }
}
function adminLogout() { sessionStorage.removeItem("teqlif_admin_session"); location.reload(); }

// Sadece 401/403 → logout; diğer hatalar (404, 500) → null döner, UI sessizce görmezden gelir
async function adminFetch(url, opts) {
    const res = await fetch(url, { headers: getAuthHeaders(), ...opts });
    if (res.status === 401 || res.status === 403) { adminLogout(); return null; }
    if (!res.ok) return null;
    return res;
}

// ── NAVIGATION ────────────────────────────────────────────────────────────────
function showFinalStep() {
    document.getElementById("auth-container").classList.add("hidden");
    document.getElementById("admin-content").classList.remove("hidden");
    showPanel('dashboard');
}

function showPanel(panel) {
    document.querySelectorAll('.panel-content').forEach(p => { p.classList.add('hidden'); p.style.display = 'none'; });
    document.querySelectorAll('.nav-item').forEach(p => p.classList.remove('active'));

    const activePanel = document.getElementById(`panel-${panel}`);
    if (activePanel) { activePanel.classList.remove('hidden'); activePanel.style.display = 'flex'; }

    const navMap = {
        dashboard: 'navDashboard', users: 'navUsers', tuci: 'navTuci',
        campaigns: 'navCampaigns', streams: 'navStreams',
        'stream-history': 'navStreamHistory', listings: 'navListings',
        reports: 'navReports', push: 'navPush', analytics: 'navAnalytics',
        config: 'navConfig'
    };
    const navEl = document.getElementById(navMap[panel]);
    if (navEl) navEl.classList.add('active');

    if (panel === 'dashboard') loadDashboard();
    if (panel === 'users') loadUsers();
    if (panel === 'tuci') loadTuci();
    if (panel === 'campaigns') loadCampaigns();
    if (panel === 'streams') loadStreams();
    if (panel === 'stream-history') loadStreamHistory();
    if (panel === 'listings') loadListings();
    if (panel === 'reports') loadReports();
    if (panel === 'analytics') loadAnalytics();
    if (panel === 'config') loadConfig();
}

// ── SEARCH / FILTER ───────────────────────────────────────────────────────────
function filterTable(inputId, tbodyId) {
    const filter = document.getElementById(inputId).value.toLowerCase();
    const trs = document.getElementById(tbodyId).getElementsByTagName("tr");
    for (let i = 0; i < trs.length; i++) {
        if (trs[i].cells.length > 1)
            trs[i].style.display = trs[i].innerText.toLowerCase().includes(filter) ? "" : "none";
    }
}

// ── DASHBOARD ─────────────────────────────────────────────────────────────────
async function loadDashboard() {
    const res = await adminFetch('/api/admin-data/dashboard');
    if (!res) return;
    const d = await res.json();

    document.getElementById('kpiTotal').textContent = d.total_users.toLocaleString('tr-TR');
    document.getElementById('kpiActive').textContent = d.active_users.toLocaleString('tr-TR');
    document.getElementById('kpiBanned').textContent = d.banned_users.toLocaleString('tr-TR');
    document.getElementById('kpiToday').textContent = d.today_users.toLocaleString('tr-TR');
    document.getElementById('kpiListings').textContent = d.active_listings.toLocaleString('tr-TR');
    document.getElementById('kpiStreams').textContent = d.active_streams.toLocaleString('tr-TR');
    document.getElementById('kpiReports').textContent = d.pending_reports.toLocaleString('tr-TR');
    document.getElementById('kpiTuci').textContent = d.total_tuci_circulation.toLocaleString('tr-TR') + ' T';
    document.getElementById('kpiTuciSpent').textContent = d.today_tuci_spent.toLocaleString('tr-TR') + ' T';

    // Growth bar chart
    const growth = d.user_growth_7d || [];
    const maxCount = Math.max(...growth.map(g => g.count), 1);
    const chart = document.getElementById('growthChart');
    const labels = document.getElementById('growthLabels');
    chart.innerHTML = growth.map(g => {
        const h = Math.max(4, Math.round((g.count / maxCount) * 60));
        const label = g.date.slice(5); // MM-DD
        return `<div class="bar" style="height:${h}px;" data-label="${label}: ${g.count} kayıt" title="${label}: ${g.count}"></div>`;
    }).join('');
    labels.innerHTML = growth.map(g => `<div style="flex:1;text-align:center;">${g.date.slice(5)}</div>`).join('');
}

// ── KULLANICILAR ──────────────────────────────────────────────────────────────
async function loadUsers() {
    const res = await adminFetch('/api/admin-data/users/recent?limit=50');
    if (!res) return;
    const data = await res.json();
    document.getElementById("user-table-body").innerHTML = data.map(u => {
        const statusPills = [];
        if (u.deleted_at) {
            statusPills.push('<span class="status-pill" style="background:#374151;color:#9ca3af;">🗑 Silindi</span>');
        } else if (!u.is_active) {
            statusPills.push('<span class="status-pill" style="background:#ef4444;color:white;">🚫 Yasaklı</span>');
        } else {
            statusPills.push('<span class="status-pill" style="background:#10b981;color:#0f172a;">✅ Aktif</span>');
        }
        if (u.is_premium) statusPills.push('<span class="status-pill" style="background:#f59e0b;color:#0f172a;">⭐ PRO</span>');
        if (u.is_shadowbanned) statusPills.push('<span class="status-pill" style="background:#7c3aed;color:white;">👁 Gizli Kısıtlı</span>');
        if (!u.is_verified && !u.deleted_at) statusPills.push('<span class="status-pill" style="background:#f59e0b;color:#0f172a;">✉ Doğrulanmamış</span>');
        return `
        <tr>
            <td style="color:#64748b;">#${u.id}</td>
            <td>
                <a href="/profil/${u.username}" target="_blank" class="admin-link">@${u.username}</a>
                <br><small style="color:#64748b;">${u.email}</small>
            </td>
            <td style="white-space:nowrap;">${statusPills.join(' ')}</td>
            <td><span style="color:#fbbf24;font-weight:700;">${u.tuci_balance} T</span></td>
            <td><span style="color:#94a3b8;">${u.listing_count} ilan · ${u.stream_count} yayın</span></td>
            <td>${u.fcm_token ? '🟢' : '⚫'}</td>
            <td style="font-size:0.8rem;color:#64748b;">${new Date(u.created_at).toLocaleDateString('tr-TR')}</td>
            <td>
                <button data-open-modal="${u.id}"
                    data-modal-un="${u.username}"
                    data-modal-fn="${(u.full_name||'').replace(/"/g,'&quot;')}"
                    data-modal-email="${u.email}"
                    data-modal-active="${u.is_active}"
                    data-modal-shadow="${u.is_shadowbanned}"
                    data-modal-pro="${u.is_premium}"
                    class="action-btn">Yönet</button>
            </td>
        </tr>`;
    }).join("");
    document.getElementById("search-users").value = "";
}

function openModal(id, un, fn, email, act, shadow, isPro) {
    currentUserId = id;
    document.getElementById("modal-title").innerText = "@" + un;
    document.getElementById("edit-fullname").value = fn === 'null' ? '' : fn;
    document.getElementById("edit-email").value = email;
    document.getElementById("edit-active").value = act ? "true" : "false";
    document.getElementById("edit-password").value = "";
    const shadowBtn = document.getElementById("btnToggleShadowban");
    shadowBtn.textContent = shadow ? '👁 Gizli Kısıtlamayı Kaldır' : '👁 Gizli Kısıtlama (Shadowban) Uygula';
    shadowBtn.style.background = shadow ? '#6b7280' : '#7c3aed';
    const proBtn = document.getElementById("btnTogglePro");
    proBtn.textContent = isPro ? '⭐ PRO Kaldır' : '⭐ PRO Ver';
    proBtn.style.background = isPro ? '#6b7280' : '#d97706';
    document.getElementById("user-modal").classList.remove("hidden");
}
function closeModal() { document.getElementById("user-modal").classList.add("hidden"); currentUserId = null; }

async function submitUserUpdate() {
    await fetch(`/api/admin-data/users/${currentUserId}`, {
        method: 'PATCH', headers: getAuthHeaders(),
        body: JSON.stringify({ full_name: document.getElementById("edit-fullname").value, email: document.getElementById("edit-email").value, is_active: document.getElementById("edit-active").value === "true" })
    });
    closeModal(); loadUsers();
}

async function toggleShadowban() {
    if (!currentUserId) return;
    const res = await fetch(`/api/admin-data/users/${currentUserId}/shadowban`, { method: 'POST', headers: getAuthHeaders() });
    if (res.ok) { const d = await res.json(); alert(`@${d.username} → ${d.is_shadowbanned ? 'Shadowban uygulandı' : 'Shadowban kaldırıldı'}`); closeModal(); loadUsers(); }
}

async function togglePro() {
    if (!currentUserId) return;
    const res = await fetch(`/api/admin-data/users/${currentUserId}/toggle-pro`, { method: 'POST', headers: getAuthHeaders() });
    if (res.ok) { const d = await res.json(); alert(`@${d.username} → ${d.is_premium ? '⭐ PRO verildi' : 'PRO kaldırıldı'}`); closeModal(); loadUsers(); }
}

async function submitPasswordReset() {
    const p = document.getElementById("edit-password").value;
    if (p.length < 8) return alert("En az 8 karakter");
    await fetch(`/api/admin-data/users/${currentUserId}/password`, { method: 'PATCH', headers: getAuthHeaders(), body: JSON.stringify({ new_password: p }) });
    alert("Şifre Değiştirildi!"); closeModal();
}

function openAddUserModal() {
    ['new-username','new-email','new-fullname','new-password'].forEach(id => document.getElementById(id).value = '');
    document.getElementById("add-user-modal").classList.remove("hidden");
}
function closeAddUserModal() { document.getElementById("add-user-modal").classList.add("hidden"); }

async function submitNewUser() {
    const username = document.getElementById("new-username").value;
    const email = document.getElementById("new-email").value;
    const fullname = document.getElementById("new-fullname").value;
    const password = document.getElementById("new-password").value;
    if (!username || !email || !password) { alert("Zorunlu alanları doldurun."); return; }
    if (password.length < 8) { alert("Şifre en az 8 karakter."); return; }
    const res = await fetch('/api/admin-data/users', { method: 'POST', headers: getAuthHeaders(), body: JSON.stringify({ username, email, full_name: fullname, password }) });
    if (res.ok) { alert("Kullanıcı eklendi!"); closeAddUserModal(); loadUsers(); }
    else { const err = await res.json(); alert("Hata: " + (err.error?.message || "Eklenemedi.")); }
}

async function deleteUser(id, username) {
    if (!confirm(`@${username} hesabı kapatılsın mı? (Soft delete — e-posta korunur)`)) return;
    const res = await fetch(`/api/admin-data/users/${id}`, { method: 'DELETE', headers: getAuthHeaders() });
    if (res.ok) { const d = await res.json(); alert(d.message); closeModal(); loadUsers(); }
    else { const err = await res.json(); alert("Silinemedi: " + (err.detail || "Hata.")); }
}

async function purgeUser(id, username) {
    if (!confirm(`DİKKAT: @${username} kalıcı anonimize edilecek.\n\nE-posta, kullanıcı adı ve telefon temizlenecek → aynı bilgilerle yeniden kayıt açılabilir.\n\nBu işlem geri alınamaz. Devam edilsin mi?`)) return;
    const res = await fetch(`/api/admin-data/users/${id}/purge`, { method: 'POST', headers: getAuthHeaders() });
    if (res.ok) { const d = await res.json(); alert(d.message); closeModal(); loadUsers(); }
    else { const err = await res.json(); alert("Silinemedi: " + (err.detail || "Hata.")); }
}

// ── TUCi EKONOMİSİ ───────────────────────────────────────────────────────────
async function loadTuci() {
    const res = await adminFetch('/api/admin-data/tuci/summary?limit=100');
    if (!res) return;
    const d = await res.json();

    document.getElementById('tuciCirculation').textContent = d.total_circulation.toLocaleString('tr-TR') + ' T';
    document.getElementById('tuciEarned').textContent = d.total_earned.toLocaleString('tr-TR') + ' T';
    document.getElementById('tuciSpent').textContent = d.total_spent.toLocaleString('tr-TR') + ' T';

    document.getElementById('tuciTopHolders').innerHTML = (d.top_holders || []).map((h, i) => `
        <div style="background:var(--admin-bg);border:1px solid var(--admin-border);border-radius:0.5rem;padding:0.4rem 0.75rem;font-size:0.8rem;">
            <span style="color:#64748b;">${i+1}.</span>
            <a href="/profil/${h.username}" target="_blank" class="admin-link">@${h.username}</a>
            <span style="color:#fbbf24;margin-left:6px;font-weight:700;">${h.balance} T</span>
        </div>`).join('');

    const TYPE_LABELS = {
        airdrop: '🎁 Airdrop', spend_lead_gen: '🎯 Duyuru', spend_ai: '🤖 AI',
        web_topup: '💳 Topup', spend_ad_campaign: '📢 Sponsorluk',
    };
    document.getElementById('tuci-table-body').innerHTML = (d.transactions || []).map(tx => {
        const plus = tx.amount > 0;
        return `<tr>
            <td style="font-size:0.8rem;color:#64748b;">${new Date(tx.created_at).toLocaleString('tr-TR')}</td>
            <td><a href="/profil/${tx.username}" target="_blank" class="admin-link">@${tx.username}</a></td>
            <td style="font-weight:700;color:${plus ? '#10b981' : '#ef4444'}">${plus ? '+' : ''}${tx.amount} T</td>
            <td><span class="status-pill" style="background:var(--admin-bg);border:1px solid var(--admin-border);color:#94a3b8;">${TYPE_LABELS[tx.transaction_type] || tx.transaction_type}</span></td>
        </tr>`;
    }).join('');
    document.getElementById("search-tuci").value = "";
}

function openAirdropModal() {
    document.getElementById('airdrop-username').value = '';
    document.getElementById('airdrop-amount').value = '';
    document.getElementById('airdrop-modal').classList.remove('hidden');
    document.getElementById('airdrop-username').focus();
}
function closeAirdropModal() { document.getElementById('airdrop-modal').classList.add('hidden'); }

async function submitAirdrop() {
    const username = document.getElementById('airdrop-username').value.trim().replace(/^@/, '');
    const amount = parseInt(document.getElementById('airdrop-amount').value);
    if (!username) { alert("Kullanıcı adı girin."); return; }
    if (!amount || amount < 1) { alert("Geçerli bir miktar girin."); return; }
    const btn = document.getElementById('btnSubmitAirdrop');
    btn.disabled = true;
    btn.textContent = '⏳ Yükleniyor…';
    try {
        const res = await fetch('/api/admin-data/tuci/airdrop', { method: 'POST', headers: getAuthHeaders(), body: JSON.stringify({ username, amount }) });
        const d = await res.json();
        if (res.ok) {
            alert(`✅ ${d.message}\nYeni bakiye: ${d.new_balance} TUCi`);
            closeAirdropModal();
            loadTuci();
        } else {
            alert("Hata: " + (d.detail || "Airdrop başarısız."));
        }
    } finally {
        btn.disabled = false;
        btn.textContent = '🎁 Airdrop Et';
    }
}

// ── REKLAM KAMPANYALARI ───────────────────────────────────────────────────────
async function loadCampaigns() {
    const res = await adminFetch('/api/admin-data/ad-campaigns');
    if (!res) return;
    const data = await res.json();
    const STATUS_COLORS = { active: '#10b981', paused: '#f59e0b', exhausted: '#ef4444' };
    document.getElementById('campaign-table-body').innerHTML = data.length === 0
        ? '<tr><td colspan="10" style="text-align:center;">Kampanya yok.</td></tr>'
        : data.map(c => {
            const pct = c.total_budget > 0 ? Math.round(c.spent_budget / c.total_budget * 100) : 0;
            const color = STATUS_COLORS[c.status] || '#94a3b8';
            return `<tr>
                <td style="color:#64748b;">#${c.id}</td>
                <td><a href="/profil/${c.username}" target="_blank" class="admin-link">@${c.username}</a></td>
                <td><a href="/ilan/${c.listing_id}" target="_blank" class="admin-link" style="max-width:150px;display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${c.listing_title}</a></td>
                <td style="color:#fbbf24;">${c.total_budget} T</td>
                <td>${c.spent_budget} T <small style="color:#64748b;">(${pct}%)</small></td>
                <td style="color:${c.remaining > 0 ? '#10b981' : '#ef4444'}">${c.remaining} T</td>
                <td>${c.cpc_bid} T</td>
                <td><span class="status-pill" style="background:${color};color:${c.status === 'active' ? '#0f172a' : 'white'}">${c.status}</span></td>
                <td style="font-size:0.8rem;color:#64748b;">${new Date(c.created_at).toLocaleDateString('tr-TR')}</td>
                <td><button data-pause-campaign="${c.id}" class="action-btn" style="background:${c.status === 'active' ? '#f59e0b' : '#10b981'}">${c.status === 'active' ? 'Durdur' : 'Aktifleştir'}</button></td>
            </tr>`;
        }).join('');
    document.getElementById("search-campaigns").value = "";
}

async function pauseCampaign(id) {
    const res = await fetch(`/api/admin-data/ad-campaigns/${id}/pause`, { method: 'POST', headers: getAuthHeaders() });
    if (res.ok) loadCampaigns();
}

// ── AKTİF YAYINLAR ───────────────────────────────────────────────────────────
async function loadStreams() {
    const res = await adminFetch('/api/admin-data/streams/active');
    if (!res) return;
    const data = await res.json();
    document.getElementById("stream-table-body").innerHTML = data.length === 0
        ? '<tr><td colspan="7" style="text-align:center;">Aktif yayın yok.</td></tr>'
        : data.map(s => `
            <tr>
                <td style="font-family:monospace;font-size:0.8rem;color:#64748b;">${s.room_name.substring(0,12)}…</td>
                <td><a href="/profil/${s.host_username}" target="_blank" class="admin-link">@${s.host_username}</a></td>
                <td>${s.title || '—'}</td>
                <td><span class="status-pill" style="background:#334155;color:#94a3b8;">${s.category || '—'}</span></td>
                <td><span class="status-pill" style="background:#3b82f6;color:white;">👁 ${s.viewer_count}</span></td>
                <td>${Math.floor((Date.now() - new Date(s.started_at)) / 60000)} dk</td>
                <td><button data-end-stream="${s.id}" class="action-btn" style="background:var(--admin-danger);">Kapat</button></td>
            </tr>`).join("");
    document.getElementById("search-streams").value = "";
}

async function endStream(id) {
    if (!confirm("Yayını zorla kapatmak istiyor musunuz?")) return;
    await fetch(`/api/admin-data/streams/${id}/end`, { method: 'POST', headers: getAuthHeaders() });
    loadStreams();
}

// ── YAYIN GEÇMİŞİ ────────────────────────────────────────────────────────────
async function loadStreamHistory() {
    const res = await adminFetch('/api/admin-data/streams/history?limit=50');
    if (!res) return;
    const data = await res.json();
    document.getElementById('stream-history-table-body').innerHTML = data.length === 0
        ? '<tr><td colspan="7" style="text-align:center;">Yayın geçmişi yok.</td></tr>'
        : data.map(s => `
            <tr>
                <td style="color:#64748b;">#${s.id}</td>
                <td><a href="/profil/${s.host_username}" target="_blank" class="admin-link">@${s.host_username}</a></td>
                <td>${s.title || '—'}</td>
                <td><span class="status-pill" style="background:#334155;color:#94a3b8;">${s.category || '—'}</span></td>
                <td>${s.duration_min != null ? s.duration_min + ' dk' : '—'}</td>
                <td>${s.viewer_count}</td>
                <td style="font-size:0.8rem;color:#64748b;">${new Date(s.started_at).toLocaleString('tr-TR')}</td>
            </tr>`).join('');
    document.getElementById("search-stream-history").value = "";
}

// ── İLAN DENETİMİ ────────────────────────────────────────────────────────────
async function loadListings() {
    const res = await adminFetch('/api/admin-data/listings?limit=50');
    if (!res) return;
    const data = await res.json();
    document.getElementById("listing-table-body").innerHTML = data.length === 0
        ? '<tr><td colspan="6" style="text-align:center;">İlan bulunamadı.</td></tr>'
        : data.map(l => `
            <tr style="opacity:${l.is_deleted ? '0.5' : '1'};">
                <td style="color:#64748b;">#${l.id}</td>
                <td><a href="/ilan/${l.id}" target="_blank" class="admin-link">${l.title}</a></td>
                <td><a href="/profil/${l.username}" target="_blank" class="admin-link">@${l.username}</a></td>
                <td>${l.price != null ? '₺' + Number(l.price).toLocaleString('tr-TR') : '—'}</td>
                <td>${l.is_deleted ? '🗑 Silinmiş' : (l.is_active ? '✅ Aktif' : '⏸ Pasif')}</td>
                <td>${!l.is_deleted ? `<button data-toggle-listing="${l.id}" class="action-btn" style="background:var(--admin-warn);">${l.is_active ? 'Pasife Al' : 'Aktifleştir'}</button>
                    <button data-delete-listing="${l.id}" class="action-btn" style="background:var(--admin-danger);">Sil</button>` : '—'}</td>
            </tr>`).join("");
    document.getElementById("search-listings").value = "";
}

async function toggleListing(id) { await fetch(`/api/admin-data/listings/${id}/toggle`, { method: 'POST', headers: getAuthHeaders() }); loadListings(); }
async function deleteListing(id) {
    if (confirm("İlanı silmek istediğinize emin misiniz?")) { await fetch(`/api/admin-data/listings/${id}`, { method: 'DELETE', headers: getAuthHeaders() }); loadListings(); }
}

// ── ŞİKAYETLER ───────────────────────────────────────────────────────────────
async function loadReports() {
    const res = await adminFetch('/api/admin-data/reports?limit=50');
    if (!res) return;
    const data = await res.json();
    document.getElementById("report-table-body").innerHTML = data.length === 0
        ? '<tr><td colspan="6" style="text-align:center;">Şikayet bulunamadı.</td></tr>'
        : data.map(r => `
            <tr>
                <td style="color:#64748b;">#${r.id}</td>
                <td><a href="${r.reporter_url}" target="_blank" class="admin-link">@${r.reporter}</a></td>
                <td><a href="${r.target_url}" target="_blank" class="admin-link" style="color:#fca5a5;">${r.target}</a></td>
                <td>${r.reason}</td>
                <td>${r.status === 'resolved' ? '<span class="status-pill" style="background:#10b981;color:#0f172a;">Çözüldü</span>' : '<span class="status-pill" style="background:#f59e0b;color:#0f172a;">Bekliyor</span>'}</td>
                <td>${r.status !== 'resolved' ? `<button data-resolve-report="${r.id}" class="action-btn" style="background:var(--admin-primary);">Çözüldü</button>` : '—'}</td>
            </tr>`).join("");
    document.getElementById("search-reports").value = "";
}
async function resolveReport(id) { await fetch(`/api/admin-data/reports/${id}/resolve`, { method: 'POST', headers: getAuthHeaders() }); loadReports(); }

// ── PUSH BİLDİRİMİ ───────────────────────────────────────────────────────────
async function sendPush() {
    const userId = document.getElementById('pushUserId').value;
    const title = document.getElementById('pushTitle').value.trim();
    const body = document.getElementById('pushBody').value.trim();
    if (!title || !body) { alert("Başlık ve içerik zorunlu."); return; }

    const payload = { title, body };
    const userIdTrimmed = userId.trim();
    if (userIdTrimmed) {
        const parsed = parseInt(userIdTrimmed, 10);
        if (isNaN(parsed) || parsed <= 0) { alert("Geçersiz kullanıcı ID. Sayısal bir ID girin ya da boş bırakın."); return; }
        payload.user_id = parsed;
    }

    const resultEl = document.getElementById('pushResult');
    resultEl.textContent = 'Gönderiliyor…';
    const res = await fetch('/api/admin-data/push/send', { method: 'POST', headers: getAuthHeaders(), body: JSON.stringify(payload) });
    if (res.ok) {
        const d = await res.json();
        resultEl.style.color = '#10b981';
        resultEl.textContent = `✅ Gönderildi: ${d.sent} kişi${d.total_tokens ? ' / ' + d.total_tokens + ' token' : ''}`;
    } else {
        const err = await res.json();
        resultEl.style.color = '#ef4444';
        resultEl.textContent = '❌ Hata: ' + (err.detail || 'Gönderilemedi.');
    }
}

// ── ANALİTİK ─────────────────────────────────────────────────────────────────
async function loadAnalytics() {
    const res = await adminFetch('/api/admin-data/analytics/summary');
    if (!res) return;
    const data = await res.json();

    document.getElementById("analytics-total").textContent = data.total_events.toLocaleString('tr-TR');
    document.getElementById("analytics-unique").textContent = data.unique_sessions.toLocaleString('tr-TR');

    const devs = data.device_stats.map(d => `<div><span style="color:#64748b;font-size:0.8rem">${(d.device||'-').toUpperCase()}</span><br><b>${d.count}</b></div>`).join('');
    document.getElementById("analytics-devices").innerHTML = devs || "<span>Veri Yok</span>";

    document.getElementById("analytics-table-body").innerHTML = data.recent_events.length === 0
        ? '<tr><td colspan="6" style="text-align:center;">Kayıt bulunamadı.</td></tr>'
        : data.recent_events.map(e => {
            const metaStr = Object.keys(e.metadata).length > 0
                ? Object.entries(e.metadata).map(([k,v]) => `<span style="background:rgba(255,255,255,0.08);padding:2px 4px;border-radius:4px;margin-right:4px;"><b>${k}</b>: ${v}</span>`).join('')
                : '—';
            return `<tr>
                <td style="font-size:0.8rem;color:#94a3b8;">${new Date(e.created_at).toLocaleString('tr-TR')}</td>
                <td style="font-family:monospace;color:#64748b;">${e.session_id.substring(0,8)}…</td>
                <td><span class="status-pill" style="background:var(--admin-card);border:1px solid var(--admin-border);color:#38bdf8;">${e.event_type}</span></td>
                <td>${e.device} · ${e.brand}</td>
                <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${e.url}</td>
                <td style="font-size:0.78rem;color:#cbd5e1;max-width:280px;line-height:1.5;">${metaStr}</td>
            </tr>`;
        }).join('');
    document.getElementById("search-analytics").value = "";
}

// ── EVENT LISTENERS ───────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', function () {
    // Auth
    const pwInput = document.getElementById('adminPasswordInput');
    if (pwInput) pwInput.addEventListener('keypress', e => { if (e.key === 'Enter') verifyPassword(); });
    document.getElementById('btnVerifyPassword')?.addEventListener('click', verifyPassword);
    document.getElementById('btnAdminLogout')?.addEventListener('click', adminLogout);

    // Nav
    document.getElementById('navDashboard')?.addEventListener('click', () => showPanel('dashboard'));
    document.getElementById('navUsers')?.addEventListener('click', () => showPanel('users'));
    document.getElementById('navTuci')?.addEventListener('click', () => showPanel('tuci'));
    document.getElementById('navCampaigns')?.addEventListener('click', () => showPanel('campaigns'));
    document.getElementById('navStreams')?.addEventListener('click', () => showPanel('streams'));
    document.getElementById('navStreamHistory')?.addEventListener('click', () => showPanel('stream-history'));
    document.getElementById('navListings')?.addEventListener('click', () => showPanel('listings'));
    document.getElementById('navReports')?.addEventListener('click', () => showPanel('reports'));
    document.getElementById('navPush')?.addEventListener('click', () => showPanel('push'));
    document.getElementById('navAnalytics')?.addEventListener('click', () => showPanel('analytics'));
    document.getElementById('navConfig')?.addEventListener('click', () => showPanel('config'));

    // Reload buttons
    document.getElementById('btnLoadDashboard')?.addEventListener('click', loadDashboard);
    document.getElementById('btnLoadUsers')?.addEventListener('click', loadUsers);
    document.getElementById('btnLoadTuci')?.addEventListener('click', loadTuci);
    document.getElementById('btnLoadCampaigns')?.addEventListener('click', loadCampaigns);
    document.getElementById('btnLoadStreams')?.addEventListener('click', loadStreams);
    document.getElementById('btnLoadStreamHistory')?.addEventListener('click', loadStreamHistory);
    document.getElementById('btnLoadListings')?.addEventListener('click', loadListings);
    document.getElementById('btnLoadReports')?.addEventListener('click', loadReports);
    document.getElementById('btnLoadAnalytics')?.addEventListener('click', loadAnalytics);

    // Search
    document.getElementById('search-users')?.addEventListener('keyup', () => filterTable('search-users', 'user-table-body'));
    document.getElementById('search-tuci')?.addEventListener('keyup', () => filterTable('search-tuci', 'tuci-table-body'));
    document.getElementById('search-campaigns')?.addEventListener('keyup', () => filterTable('search-campaigns', 'campaign-table-body'));
    document.getElementById('search-streams')?.addEventListener('keyup', () => filterTable('search-streams', 'stream-table-body'));
    document.getElementById('search-stream-history')?.addEventListener('keyup', () => filterTable('search-stream-history', 'stream-history-table-body'));
    document.getElementById('search-listings')?.addEventListener('keyup', () => filterTable('search-listings', 'listing-table-body'));
    document.getElementById('search-reports')?.addEventListener('keyup', () => filterTable('search-reports', 'report-table-body'));
    document.getElementById('search-analytics')?.addEventListener('keyup', () => filterTable('search-analytics', 'analytics-table-body'));

    // User modal
    document.getElementById('btnCloseEditModal')?.addEventListener('click', closeModal);
    document.getElementById('btnSubmitUserUpdate')?.addEventListener('click', submitUserUpdate);
    document.getElementById('btnTogglePro')?.addEventListener('click', togglePro);
    document.getElementById('btnToggleShadowban')?.addEventListener('click', toggleShadowban);
    document.getElementById('btnSoftDeleteUser')?.addEventListener('click', () => { if (currentUserId) deleteUser(currentUserId, (document.getElementById('modal-title')?.innerText || '').replace('@','')); });
    document.getElementById('btnPurgeUser')?.addEventListener('click', () => { if (currentUserId) purgeUser(currentUserId, (document.getElementById('modal-title')?.innerText || '').replace('@','')); });
    document.getElementById('btnSubmitPasswordReset')?.addEventListener('click', submitPasswordReset);
    document.getElementById('btnOpenAddUser')?.addEventListener('click', openAddUserModal);
    document.getElementById('btnCloseAddUserModal')?.addEventListener('click', closeAddUserModal);
    document.getElementById('btnSubmitNewUser')?.addEventListener('click', submitNewUser);

    // Airdrop modal
    document.getElementById('btnAirdropModal')?.addEventListener('click', openAirdropModal);
    document.getElementById('btnCloseAirdropModal')?.addEventListener('click', closeAirdropModal);
    document.getElementById('btnSubmitAirdrop')?.addEventListener('click', submitAirdrop);

    // Push
    document.getElementById('btnSendPush')?.addEventListener('click', sendPush);

    // Event delegation — dynamic table buttons
    document.getElementById('user-table-body')?.addEventListener('click', e => {
        const openBtn = e.target.closest('[data-open-modal]');
        if (openBtn) { openModal(Number(openBtn.dataset.openModal), openBtn.dataset.modalUn, openBtn.dataset.modalFn, openBtn.dataset.modalEmail, openBtn.dataset.modalActive === 'true', openBtn.dataset.modalShadow === 'true', openBtn.dataset.modalPro === 'true'); return; }
    });

    document.getElementById('stream-table-body')?.addEventListener('click', e => {
        const btn = e.target.closest('[data-end-stream]');
        if (btn) endStream(Number(btn.dataset.endStream));
    });

    document.getElementById('campaign-table-body')?.addEventListener('click', e => {
        const btn = e.target.closest('[data-pause-campaign]');
        if (btn) pauseCampaign(Number(btn.dataset.pauseCampaign));
    });

    document.getElementById('listing-table-body')?.addEventListener('click', e => {
        const toggleBtn = e.target.closest('[data-toggle-listing]');
        if (toggleBtn) { toggleListing(Number(toggleBtn.dataset.toggleListing)); return; }
        const delBtn = e.target.closest('[data-delete-listing]');
        if (delBtn) deleteListing(Number(delBtn.dataset.deleteListing));
    });

    document.getElementById('report-table-body')?.addEventListener('click', e => {
        const btn = e.target.closest('[data-resolve-report]');
        if (btn) resolveReport(Number(btn.dataset.resolveReport));
    });
});


// SÜRÜM YÖNETİMİ BAŞLANGIÇ
const btnLoadConfig = document.getElementById('btnLoadConfig');
const btnSaveConfig = document.getElementById('btnSaveConfig');

if(btnLoadConfig) btnLoadConfig.addEventListener('click', loadConfig);
if(btnSaveConfig) btnSaveConfig.addEventListener('click', saveConfig);

async function loadConfig() {
    try {
        const res = await fetch('/api/config/version', {
            headers: getAuthHeaders()
        });
        if (!res.ok) throw new Error('Ayar okuma hatası');
        const data = await res.json();
        
        document.getElementById('configIosMin').value = data.ios.min_version || '';
        document.getElementById('configIosLatest').value = data.ios.latest_version || '';
        document.getElementById('configAndroidMin').value = data.android.min_version || '';
        document.getElementById('configAndroidLatest').value = data.android.latest_version || '';
        
        alert('Ayarlar yüklendi');
    } catch (e) {
        alert(e.message);
    }
}

async function saveConfig() {
    const payload = {
        ios_min_version: document.getElementById('configIosMin').value.trim(),
        ios_latest_version: document.getElementById('configIosLatest').value.trim(),
        android_min_version: document.getElementById('configAndroidMin').value.trim(),
        android_latest_version: document.getElementById('configAndroidLatest').value.trim()
    };
    
    try {
        const res = await fetch('/api/config/version', {
            method: 'POST',
            headers: getAuthHeaders(),
            body: JSON.stringify(payload)
        });
        if (!res.ok) throw new Error('Kaydetme hatası');
        alert('Ayarlar başarıyla kaydedildi!');
    } catch(e) {
        alert(e.message);
    }
}

// SÜRÜM YÖNETİMİ BİTİŞ

