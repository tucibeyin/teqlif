    if (!Auth.getToken()) window.location.href = '/giris.html';

    const user = Auth.getUser();

    function renderProfile(u) {
        if (!u) return;
        document.getElementById('loadingState').style.display = 'none';
        document.getElementById('profileCard').style.display = '';
        document.getElementById('menuSections').style.display = '';
        document.getElementById('menuAccount').style.display = '';
        document.getElementById('menuSupport').style.display = '';
        document.getElementById('menuDanger').style.display = '';

        const initial = (u.full_name || u.username || '?')[0].toUpperCase();
        const avatarEl = document.getElementById('avatarEl');
        const initialEl = document.getElementById('avatarInitial');
        // Mevcut img varsa kaldır
        const existingImg = avatarEl.querySelector('img');
        if (existingImg) existingImg.remove();

        if (u.profile_image_url) {
            initialEl.style.display = 'none';
            const img = document.createElement('img');
            img.src = u.profile_image_url;
            img.alt = 'Profil fotoğrafı';
            avatarEl.insertBefore(img, avatarEl.firstChild);
        } else {
            initialEl.style.display = '';
            initialEl.textContent = initial;
        }

        document.getElementById('fullNameEl').textContent = u.full_name || u.username;
        document.getElementById('usernameEl').textContent = '@' + u.username;
        document.getElementById('emailEl').textContent = u.email || '';

        // Formlara doldur
        document.getElementById('editFullName').value = u.full_name || '';
        document.getElementById('editUsername').value = u.username || '';
    }

    // Avatar upload
    document.getElementById('avatarInput').addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const formData = new FormData();
        formData.append('file', file);
        try {
            const uploadResp = await fetch('/api/upload', {
                method: 'POST',
                headers: { 'Authorization': 'Bearer ' + Auth.getToken() },
                body: formData,
            });
            if (!uploadResp.ok) throw new Error('Yükleme başarısız');
            const { url } = await uploadResp.json();
            const updated = await apiFetch('/auth/me', {
                method: 'PATCH',
                body: JSON.stringify({ profile_image_url: url }),
            });
            const stored = Auth.getUser();
            if (stored) {
                stored.profile_image_url = updated.profile_image_url;
                localStorage.setItem('teqlif_user', JSON.stringify(stored));
            }
            renderProfile(updated);
        } catch (err) {
            alert('Fotoğraf yüklenemedi. Lütfen tekrar deneyin.');
        }
        e.target.value = '';
    });

    // Önce localStorage'dan hızlı render
    if (user) renderProfile(user);

    // Sonra API'den taze veri al
    Auth.me().then(u => renderProfile(u)).catch(() => {
        document.getElementById('loadingState').style.display = 'none';
    });

    /* ── Modal yardımcıları ─────────────────────────────────────── */
    function openModal(id) {
        const m = document.getElementById(id);
        m.style.display = 'flex';
    }
    function closeModal(id) {
        document.getElementById(id).style.display = 'none';
    }

    // ── Profil düzenle — kullanıcı adı gerçek zamanlı kontrol ────
    let _editUnTimer = null;
    let _editUnOk = null; // null=değişmedi veya kontrol edilmedi, true=uygun, false=alınmış
    const _editUnInput = document.getElementById('editUsername');
    const _editUnStatus = document.getElementById('editUsernameStatus');

    _editUnInput.addEventListener('input', () => {
        const val = _editUnInput.value.trim();
        const originalUsername = (Auth.getUser() || {}).username || '';
        clearTimeout(_editUnTimer);
        _editUnOk = null;
        _editUnStatus.textContent = '';
        if (val === originalUsername) return; // Değişmedi, kontrol gerekmiyor
        if (!/^[a-z0-9_]+$/.test(val)) {
            if (val) {
                _editUnStatus.textContent = '⚠ Sadece küçük harf, rakam ve _ kullanılabilir';
                _editUnStatus.style.color = '#ef4444';
            }
            return;
        }
        if (val.length < 3) return;
        _editUnStatus.textContent = 'Kontrol ediliyor...';
        _editUnStatus.style.color = '#6b7280';
        _editUnTimer = setTimeout(async () => {
            try {
                const currentUser = Auth.getUser();
                const excludeId = currentUser ? currentUser.id : '';
                const params = new URLSearchParams({ username: val });
                if (excludeId) params.append('exclude_id', excludeId);
                const r = await fetch('/api/auth/check-username?' + params.toString());
                const d = await r.json();
                if (d.available) {
                    _editUnStatus.textContent = '✓ Kullanıcı adı uygun';
                    _editUnStatus.style.color = '#16a34a';
                    _editUnOk = true;
                } else {
                    _editUnStatus.textContent = '✗ Bu kullanıcı adı zaten alınmış';
                    _editUnStatus.style.color = '#ef4444';
                    _editUnOk = false;
                }
            } catch { _editUnStatus.textContent = ''; _editUnOk = null; }
        }, 600);
    });

    // Profil düzenle
    document.getElementById('menuEditProfile').addEventListener('click', (e) => {
        e.preventDefault();
        // Modal açıldığında status sıfırla
        _editUnOk = null;
        _editUnStatus.textContent = '';
        openModal('editModal');
    });

    document.getElementById('btnSaveProfile').addEventListener('click', async () => {
        const btn = document.getElementById('btnSaveProfile');
        const alertEl = document.getElementById('editAlert');
        const fullName = document.getElementById('editFullName').value.trim();
        const username = document.getElementById('editUsername').value.trim();

        if (!fullName || !username) {
            alertEl.textContent = 'Tüm alanları doldurun.';
            alertEl.style.display = 'block';
            return;
        }
        if (!/^[a-z0-9_]{3,50}$/.test(username)) {
            alertEl.textContent = 'Kullanıcı adı geçersiz. Sadece küçük harf, rakam ve _ kullanılabilir (min 3 karakter).';
            alertEl.style.display = 'block';
            return;
        }
        if (_editUnOk === false) {
            alertEl.textContent = 'Bu kullanıcı adı zaten alınmış. Lütfen başka bir tane seçin.';
            alertEl.style.display = 'block';
            return;
        }

        btn.disabled = true;
        btn.textContent = 'Kaydediliyor...';
        alertEl.style.display = 'none';

        try {
            const updated = await apiFetch('/auth/me', {
                method: 'PATCH',
                body: JSON.stringify({ full_name: fullName, username }),
            });
            // localStorage güncelle
            const stored = Auth.getUser();
            if (stored) {
                stored.full_name = updated.full_name || fullName;
                stored.username = updated.username || username;
                localStorage.setItem('teqlif_user', JSON.stringify(stored));
            }
            renderProfile(updated);
            closeModal('editModal');
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Kaydedilemedi.';
            alertEl.style.display = 'block';
        } finally {
            btn.disabled = false;
            btn.textContent = 'Kaydet';
        }
    });

    // Şifre değiştir
    document.getElementById('menuChangePass').addEventListener('click', (e) => {
        e.preventDefault();
        openModal('passModal');
    });

    document.getElementById('btnSavePass').addEventListener('click', async () => {
        const btn = document.getElementById('btnSavePass');
        const alertEl = document.getElementById('passAlert');
        const current = document.getElementById('currentPass').value;
        const next = document.getElementById('newPass').value;
        const next2 = document.getElementById('newPass2').value;

        if (!current || !next || !next2) {
            alertEl.textContent = 'Tüm alanları doldurun.';
            alertEl.style.display = 'block';
            return;
        }
        if (next !== next2) {
            alertEl.textContent = 'Yeni şifreler eşleşmiyor.';
            alertEl.style.display = 'block';
            return;
        }
        if (next.length < 6) {
            alertEl.textContent = 'Şifre en az 6 karakter olmalı.';
            alertEl.style.display = 'block';
            return;
        }

        btn.disabled = true;
        btn.textContent = 'Değiştiriliyor...';
        alertEl.style.display = 'none';

        try {
            await apiFetch('/auth/change-password', {
                method: 'POST',
                body: JSON.stringify({ current_password: current, new_password: next }),
            });
            document.getElementById('currentPass').value = '';
            document.getElementById('newPass').value = '';
            document.getElementById('newPass2').value = '';
            closeModal('passModal');
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Şifre değiştirilemedi.';
            alertEl.style.display = 'block';
        } finally {
            btn.disabled = false;
            btn.textContent = 'Değiştir';
        }
    });

    // Hesabı Sil
    document.getElementById('menuDeleteAccount').addEventListener('click', (e) => {
        e.preventDefault();
        document.getElementById('deletePass').value = '';
        document.getElementById('deleteAlert').style.display = 'none';
        openModal('deleteModal');
    });

    document.getElementById('btnConfirmDelete').addEventListener('click', async () => {
        const btn = document.getElementById('btnConfirmDelete');
        const alertEl = document.getElementById('deleteAlert');
        const pass = document.getElementById('deletePass').value;

        if (!pass) {
            alertEl.textContent = 'Şifrenizi girin.';
            alertEl.style.display = 'block';
            return;
        }

        btn.disabled = true;
        btn.textContent = 'Siliniyor...';
        alertEl.style.display = 'none';

        try {
            await apiFetch('/auth/delete-account', {
                method: 'DELETE',
                body: JSON.stringify({ password: pass }),
            });
            Auth.logout();
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Hesap silinemedi. Şifrenizi kontrol edin.';
            alertEl.style.display = 'block';
            btn.disabled = false;
            btn.textContent = 'Hesabı Sil';
        }
    });

    // Modal dışına tıklayınca kapat
    ['editModal', 'passModal', 'deleteModal'].forEach(id => {
        document.getElementById(id).addEventListener('click', (e) => {
            if (e.target.id === id) closeModal(id);
        });
    });

    // ── Engellenenler modal ────────────────────────────────────────
    function openBlockedModal() {
        document.getElementById('blockedModalBackdrop').classList.add('open');
        document.body.style.overflow = 'hidden';
        loadBlockedUsers();
    }

    function closeBlockedModal(event) {
        if (event && event.target !== document.getElementById('blockedModalBackdrop')) return;
        document.getElementById('blockedModalBackdrop').classList.remove('open');
        document.body.style.overflow = '';
    }

    async function loadBlockedUsers() {
        const body = document.getElementById('blockedModalBody');
        body.innerHTML = '<div class="blocked-empty">Yükleniyor...</div>';
        try {
            const list = await apiFetch('/users/blocked');
            renderBlockedUsers(list, body);
        } catch (_) {
            body.innerHTML = '<div class="blocked-empty">Liste yüklenemedi.</div>';
        }
    }

    function renderBlockedUsers(list, body) {
        if (!list || list.length === 0) {
            body.innerHTML = '<div class="blocked-empty">Engellenen kullanıcı yok.</div>';
            return;
        }
        body.innerHTML = list.map(u => {
            const initial = ((u.full_name || u.username || '?')[0]).toUpperCase();
            const avatarInner = u.profile_image_url
                ? `<img src="${escHtml(u.profile_image_url)}" style="width:100%;height:100%;object-fit:cover;" alt="">`
                : escHtml(initial);
            return `
                <div class="blocked-user-row" id="blocked-row-${u.id}">
                    <a class="blocked-user-avatar" href="/profil/${encodeURIComponent(u.username)}">${avatarInner}</a>
                    <div class="blocked-user-info">
                        <a class="blocked-user-name" href="/profil/${encodeURIComponent(u.username)}">${escHtml(u.full_name || u.username)}</a>
                        <div class="blocked-user-handle">@${escHtml(u.username)}</div>
                    </div>
                    <button class="btn-unblock" onclick="unblockUser('${escHtml(u.username)}', ${u.id}, this)">Engeli Kaldır</button>
                </div>`;
        }).join('');
    }

    async function unblockUser(username, userId, btn) {
        btn.disabled = true;
        btn.textContent = '...';
        try {
            await apiFetch(`/users/${encodeURIComponent(username)}/block`, { method: 'DELETE' });
            const row = document.getElementById(`blocked-row-${userId}`);
            if (row) row.remove();
            // Eğer hiç kalmadıysa boş mesaj göster
            const body = document.getElementById('blockedModalBody');
            if (body && !body.querySelector('.blocked-user-row')) {
                body.innerHTML = '<div class="blocked-empty">Engellenen kullanıcı yok.</div>';
            }
        } catch (_) {
            btn.disabled = false;
            btn.textContent = 'Engeli Kaldır';
            alert('İşlem gerçekleştirilemedi.');
        }
    }

    function escHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') closeBlockedModal(null);
    });
