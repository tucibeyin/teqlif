    const GOOGLE_CLIENT_ID = "232766108005-c193qv63qkv5c6m3c2klrs2ihoj7b2ok.apps.googleusercontent.com";
    let currentUserId = null;

    window.onload = function () {
        if (sessionStorage.getItem("teqlif_admin_session")) { showFinalStep(); } else { initGoogleAuth(); }
    };

    function getAuthHeaders() {
        return { 'Content-Type': 'application/json', 'Authorization': `Bearer ${sessionStorage.getItem("teqlif_admin_session")}` };
    }

    // --- AUTH ---
    function initGoogleAuth() {
        google.accounts.id.initialize({ client_id: GOOGLE_CLIENT_ID, callback: handleCredentialResponse });
        google.accounts.id.renderButton(document.getElementById("buttonDiv"), { theme: "outline", size: "large", width: "100%" });
    }
    async function handleCredentialResponse(r) {
        const res = await fetch('/api/admin-auth/verify-google', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: r.credential }) });
        if (res.ok) { document.getElementById("step-google").classList.add("hidden"); document.getElementById("step-password").classList.remove("hidden"); document.getElementById("admin-pass").focus(); }
        else { alert("Erişim reddedildi."); }
    }
    async function verifyPassword() {
        const p = document.getElementById("admin-pass").value;
        const res = await fetch('/api/admin-auth/verify-password', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: p }) });
        if (res.ok) { const data = await res.json(); sessionStorage.setItem("teqlif_admin_session", data.access_token); showFinalStep(); }
        else { alert("Hatalı şifre!"); }
    }
    function adminLogout() { sessionStorage.removeItem("teqlif_admin_session"); location.reload(); }

    // --- NAVIGATION & UTILS ---
    function showFinalStep() {
        document.getElementById("auth-container").classList.add("hidden");
        document.getElementById("admin-content").classList.remove("hidden");
        showPanel('users');
    }
    function showPanel(panel) {
        document.querySelectorAll('.panel-content').forEach(p => { p.classList.add('hidden'); p.style.display = 'none'; });
        document.querySelectorAll('.nav-item').forEach(p => p.classList.remove('active'));

        const activePanel = document.getElementById(`panel-${panel}`);
        activePanel.classList.remove('hidden');
        activePanel.style.display = 'flex';

        if (event && event.target.classList.contains('nav-item')) event.target.classList.add('active');

        if (panel === 'users') loadUsers();
        if (panel === 'streams') loadStreams();
        if (panel === 'listings') loadListings();
        if (panel === 'reports') loadReports();
        if (panel === 'analytics') loadAnalytics();
    }

    // --- ARAMA / FİLTRELEME FONKSİYONU ---
    function filterTable(inputId, tbodyId) {
        const input = document.getElementById(inputId);
        const filter = input.value.toLowerCase();
        const tbody = document.getElementById(tbodyId);
        const trs = tbody.getElementsByTagName("tr");

        for (let i = 0; i < trs.length; i++) {
            if (trs[i].cells.length > 1) {
                const rowText = trs[i].innerText.toLowerCase();
                trs[i].style.display = rowText.includes(filter) ? "" : "none";
            }
        }
    }

    // --- USERS: LİSTELEME & DÜZENLEME ---
    async function loadUsers() {
        const res = await fetch('/api/admin-data/users/recent?limit=50', { headers: getAuthHeaders() });
        if (!res.ok) return adminLogout();
        const data = await res.json();
        document.getElementById("user-table-body").innerHTML = data.map(u => `
            <tr>
                <td>#${u.id}</td>
                <td><a href="/profil/${u.username}" target="_blank" class="admin-link">@${u.username}</a><br><small style="color:#64748b">${u.email}</small></td>
                <td>${u.is_active ? '<span class="status-pill" style="background:#10b981; color:#0f172a">Aktif</span>' : '<span class="status-pill" style="background:#ef4444; color:white">Yasaklı</span>'}</td>
                <td>${new Date(u.created_at).toLocaleDateString('tr-TR')}</td>
                <td>
                    <button onclick="openModal(${u.id}, '${u.username}', '${u.full_name}', '${u.email}', ${u.is_active})" class="action-btn">Yönet</button>
                    <button onclick="deleteUser(${u.id}, '${u.username}')" class="action-btn" style="background: var(--admin-danger);">Sil</button>
                </td>
            </tr>`).join("");
        document.getElementById("search-users").value = "";
    }

    function openModal(id, un, fn, email, act) {
        currentUserId = id; document.getElementById("modal-title").innerText = "@" + un;
        document.getElementById("edit-fullname").value = fn === 'null' ? '' : fn;
        document.getElementById("edit-email").value = email;
        document.getElementById("edit-active").value = act ? "true" : "false";
        document.getElementById("edit-password").value = "";
        document.getElementById("user-modal").classList.remove("hidden");
    }
    function closeModal() { document.getElementById("user-modal").classList.add("hidden"); currentUserId = null; }

    async function submitUserUpdate() {
        await fetch(`/api/admin-data/users/${currentUserId}`, { method: 'PATCH', headers: getAuthHeaders(), body: JSON.stringify({ full_name: document.getElementById("edit-fullname").value, email: document.getElementById("edit-email").value, is_active: document.getElementById("edit-active").value === "true" }) });
        closeModal(); loadUsers();
    }

    async function submitPasswordReset() {
        const p = document.getElementById("edit-password").value; if (p.length < 8) return alert("En az 8 karakter");
        await fetch(`/api/admin-data/users/${currentUserId}/password`, { method: 'PATCH', headers: getAuthHeaders(), body: JSON.stringify({ new_password: p }) });
        alert("Şifre Değiştirildi!"); closeModal();
    }

    // --- USERS: YENİ KULLANICI EKLEME ---
    function openAddUserModal() {
        document.getElementById("new-username").value = "";
        document.getElementById("new-email").value = "";
        document.getElementById("new-fullname").value = "";
        document.getElementById("new-password").value = "";
        document.getElementById("add-user-modal").classList.remove("hidden");
    }
    function closeAddUserModal() { document.getElementById("add-user-modal").classList.add("hidden"); }

    async function submitNewUser() {
        const username = document.getElementById("new-username").value;
        const email = document.getElementById("new-email").value;
        const fullname = document.getElementById("new-fullname").value;
        const password = document.getElementById("new-password").value;

        if (!username || !email || !password) { alert("Lütfen zorunlu alanları doldurun."); return; }
        if (password.length < 8) { alert("Şifre en az 8 karakter olmalıdır."); return; }

        const res = await fetch(`/api/admin-data/users`, {
            method: 'POST', headers: getAuthHeaders(),
            body: JSON.stringify({ username: username, email: email, full_name: fullname, password: password })
        });

        if (res.ok) {
            alert("Kullanıcı başarıyla eklendi!");
            closeAddUserModal(); loadUsers();
        } else {
            const err = await res.json();
            alert("Hata: " + (err.error?.message || "Kullanıcı eklenemedi."));
        }
    }

    // --- USERS: SİLME (HARD DELETE) ---
    async function deleteUser(id, username) {
        if (!confirm(`DİKKAT: @${username} adlı kullanıcıyı veritabanından kalıcı olarak silmek istediğinize emin misiniz?\n\nNot: Eğer bu kullanıcının sistemde ilanları veya mesajları varsa silme işlemi güvenlik gereği iptal edilecektir.`)) return;

        const res = await fetch(`/api/admin-data/users/${id}`, { method: 'DELETE', headers: getAuthHeaders() });

        if (res.ok) {
            alert(`@${username} başarıyla silindi.`); loadUsers();
        } else {
            const err = await res.json();
            alert("Silinemedi: " + (err.error?.message || "Sistemde ilişkili verisi var."));
        }
    }

    // --- STREAMS ---
    async function loadStreams() {
        const res = await fetch('/api/admin-data/streams/active', { headers: getAuthHeaders() });
        if (!res.ok) return;
        const data = await res.json();
        document.getElementById("stream-table-body").innerHTML = data.length === 0 ? `<tr><td colspan="6" style="text-align:center;">Aktif yayın yok.</td></tr>` : data.map(s => `
            <tr>
                <td style="font-family: monospace;">${s.room_name.substring(0, 15)}...</td>
                <td><a href="/profil/${s.host_username}" target="_blank" class="admin-link">@${s.host_username}</a></td>
                <td>${s.title || '-'}</td><td><span class="status-pill" style="background:#3b82f6; color:white;">👁 ${s.viewer_count}</span></td>
                <td>${Math.floor((new Date() - new Date(s.started_at)) / 60000)} dk</td>
                <td><button onclick="endStream(${s.id})" class="action-btn" style="background: var(--admin-danger);">Kapat</button></td>
            </tr>`).join("");
        document.getElementById("search-streams").value = "";
    }
    async function endStream(id) {
        if (!confirm("Yayını zorla kapatmak istiyor musunuz?")) return;
        await fetch(`/api/admin-data/streams/${id}/end`, { method: 'POST', headers: getAuthHeaders() });
        loadStreams();
    }

    // --- LISTINGS ---
    async function loadListings() {
        const res = await fetch('/api/admin-data/listings?limit=50', { headers: getAuthHeaders() });
        if (!res.ok) return;
        const data = await res.json();
        document.getElementById("listing-table-body").innerHTML = data.length === 0 ? `<tr><td colspan="6" style="text-align:center;">İlan bulunamadı.</td></tr>` : data.map(l => `
            <tr style="opacity: ${l.is_deleted ? '0.5' : '1'};">
                <td>#${l.id}</td>
                <td><a href="/ilan/${l.id}" target="_blank" class="admin-link">${l.title}</a></td>
                <td><a href="/profil/${l.username}" target="_blank" class="admin-link">@${l.username}</a></td>
                <td>${l.price != null ? '₺' + Number(l.price).toLocaleString('tr-TR') : '—'}</td>
                <td>${l.is_deleted ? '🗑 Silinmiş' : (l.is_active ? '✅ Aktif' : '⏸ Pasif')}</td>
                <td>
                    ${!l.is_deleted ? `<button onclick="toggleListing(${l.id})" class="action-btn" style="background: var(--admin-warn);">${l.is_active ? 'Pasife Al' : 'Aktifleştir'}</button>
                    <button onclick="deleteListing(${l.id})" class="action-btn" style="background: var(--admin-danger);">Sil</button>` : 'İşlem Yok'}
                </td>
            </tr>`).join("");
        document.getElementById("search-listings").value = "";
    }
    async function toggleListing(id) { await fetch(`/api/admin-data/listings/${id}/toggle`, { method: 'POST', headers: getAuthHeaders() }); loadListings(); }
    async function deleteListing(id) {
        if (confirm("İlanı silmek istediğinize emin misiniz?")) { await fetch(`/api/admin-data/listings/${id}`, { method: 'DELETE', headers: getAuthHeaders() }); loadListings(); }
    }

    // --- REPORTS ---
    async function loadReports() {
        const res = await fetch('/api/admin-data/reports?limit=50', { headers: getAuthHeaders() });
        if (!res.ok) return;
        const data = await res.json();
        document.getElementById("report-table-body").innerHTML = data.length === 0 ? `<tr><td colspan="6" style="text-align:center;">Şikayet bulunamadı.</td></tr>` : data.map(r => `
            <tr>
                <td>#${r.id}</td>
                <td><a href="${r.reporter_url}" target="_blank" class="admin-link">@${r.reporter}</a></td>
                <td><a href="${r.target_url}" target="_blank" class="admin-link" style="color: #fca5a5;">${r.target}</a></td>
                <td>${r.reason}</td>
                <td>${r.status === 'resolved' ? '<span class="status-pill" style="background:#10b981; color:#0f172a;">Çözüldü</span>' : '<span class="status-pill" style="background:#f59e0b; color:#0f172a;">Bekliyor</span>'}</td>
                <td>${r.status !== 'resolved' ? `<button onclick="resolveReport(${r.id})" class="action-btn" style="background: var(--admin-primary);">Çözüldü İşaretle</button>` : '-'}</td>
            </tr>`).join("");
        document.getElementById("search-reports").value = "";
    }
    async function resolveReport(id) { await fetch(`/api/admin-data/reports/${id}/resolve`, { method: 'POST', headers: getAuthHeaders() }); loadReports(); }

    // --- ANALYTICS ---
    async function loadAnalytics() {
        const res = await fetch('/api/admin-data/analytics/summary', { headers: getAuthHeaders() });
        if (!res.ok) return;
        const data = await res.json();
        
        document.getElementById("analytics-total").innerText = data.total_events.toLocaleString('tr-TR');
        document.getElementById("analytics-unique").innerText = data.unique_sessions.toLocaleString('tr-TR');
        
        const devs = data.device_stats.map(d => `<div><span style="color:#64748b; font-size:0.9rem">${d.device?.toUpperCase() || '-'}</span><br><b>${d.count}</b></div>`).join("");
        document.getElementById("analytics-devices").innerHTML = devs || "<span>Veri Yok</span>";

        document.getElementById("search-analytics").value = "";

        document.getElementById("analytics-table-body").innerHTML = data.recent_events.length === 0 ? `<tr><td colspan="6" style="text-align:center;">Kayıt bulunamadı.</td></tr>` : data.recent_events.map(e => {
            const metaStr = Object.keys(e.metadata).length > 0 
              ? Object.entries(e.metadata).map(([k,v]) => `<span style="background: rgba(255,255,255,0.1); padding: 2px 4px; border-radius: 4px; margin-right: 4px;"><b>${k}</b>: ${v}</span>`).join('') 
              : '-';
            
            return `<tr>
                <td style="font-size: 0.85rem; color: #94a3b8;">${new Date(e.created_at).toLocaleString('tr-TR')}</td>
                <td style="font-family: monospace; color: #64748b;">${e.session_id.substring(0, 8)}...</td>
                <td><span class="status-pill" style="background:var(--admin-card); border: 1px solid var(--admin-border); color: #38bdf8;">${e.event_type}</span></td>
                <td>${e.device} - ${e.brand}</td>
                <td style="max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${e.url}</td>
                <td style="font-size: 0.8rem; color: #cbd5e1; max-width: 300px; line-height: 1.5;">${metaStr}</td>
            </tr>`;
        }).join("");
    }
