    if (Auth.getToken()) window.location.href = '/';

    let registeredEmail = '';

    // ── Doğrulanmamış kullanıcı login'den yönlendirildiyse ────────
    (function () {
        const params = new URLSearchParams(window.location.search);
        if (params.get('verify') === '1' && params.get('email')) {
            registeredEmail = params.get('email');
            document.getElementById('stepRegister').style.display = 'none';
            document.getElementById('stepVerify').style.display = 'block';
            document.getElementById('verifySubtitle').textContent =
                registeredEmail + ' adresine 6 haneli doğrulama kodu gönderdik.';
        }
    })();

    // ── Kullanıcı adı gerçek zamanlı kontrol ─────────────────────
    let _unTimer = null;
    let _unOk = null; // null=kontrol edilmedi/geçersiz, true=uygun, false=alınmış
    const _unInput = document.getElementById('username');
    const _unStatus = document.getElementById('usernameStatus');

    _unInput.addEventListener('input', () => {
        const val = _unInput.value.trim();
        clearTimeout(_unTimer);
        _unOk = null;
        if (!val) { _unStatus.textContent = ''; return; }
        if (!/^[a-z0-9_]+$/.test(val)) {
            _unStatus.textContent = '⚠ Sadece küçük harf, rakam ve _ kullanılabilir';
            _unStatus.style.color = '#ef4444';
            return;
        }
        if (val.length < 3) {
            _unStatus.textContent = '';
            return;
        }
        _unStatus.textContent = 'Kontrol ediliyor...';
        _unStatus.style.color = '#6b7280';
        _unTimer = setTimeout(async () => {
            try {
                const r = await fetch('/api/auth/check-username?username=' + encodeURIComponent(val));
                const d = await r.json();
                if (d.available) {
                    _unStatus.textContent = '✓ Kullanıcı adı uygun';
                    _unStatus.style.color = '#16a34a';
                    _unOk = true;
                } else {
                    _unStatus.textContent = '✗ Bu kullanıcı adı zaten alınmış';
                    _unStatus.style.color = '#ef4444';
                    _unOk = false;
                }
            } catch { _unStatus.textContent = ''; _unOk = null; }
        }, 600);
    });

    // ── Telefon maskesi (0555 555 55 55 formatı) ─────────────────────────
    const phoneInput = document.getElementById('registerPhone');
    phoneInput.addEventListener('input', () => {
        let digits = phoneInput.value.replace(/\D/g, '').slice(0, 11);
        let out = '';
        if (digits.length > 0) out = digits.slice(0, 4);
        if (digits.length > 4) out += ' ' + digits.slice(4, 7);
        if (digits.length > 7) out += ' ' + digits.slice(7, 9);
        if (digits.length > 9) out += ' ' + digits.slice(9, 11);
        phoneInput.value = out;
    });

    const btn = document.getElementById('registerBtn');
    const alertEl = document.getElementById('alertRegister');

    document.getElementById('registerForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        alertEl.className = 'alert';

        const unVal = _unInput.value.trim();
        if (!/^[a-z0-9_]{3,50}$/.test(unVal)) {
            alertEl.textContent = 'Kullanıcı adı geçersiz. Sadece küçük harf, rakam ve _ kullanılabilir (min 3 karakter).';
            alertEl.className = 'alert alert-error show';
            return;
        }
        if (_unOk === false) {
            alertEl.textContent = 'Bu kullanıcı adı zaten alınmış. Lütfen başka bir tane seçin.';
            alertEl.className = 'alert alert-error show';
            return;
        }

        btn.disabled = true;
        btn.textContent = 'Kaydediliyor...';

        try {
            registeredEmail = document.getElementById('email').value.trim();
            const rawPhone = phoneInput.value.trim();
            const digits = rawPhone.replace(/\D/g, '');
            const payload = {
                full_name: document.getElementById('full_name').value.trim(),
                username: document.getElementById('username').value.trim(),
                email: registeredEmail,
                password: document.getElementById('password').value,
            };
            if (digits.length === 11) payload.phone = '+90' + digits.slice(1);

            await Auth.register(payload);
            document.getElementById('stepRegister').style.display = 'none';
            document.getElementById('stepVerify').style.display = 'block';
            document.getElementById('verifySubtitle').textContent =
                registeredEmail + ' adresine 6 haneli doğrulama kodu gönderdik.';
            document.getElementById('code').focus();
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Bir hata oluştu';
            alertEl.className = 'alert alert-error show';
            btn.disabled = false;
            btn.textContent = 'Kayıt Ol';
        }
    });

    document.getElementById('verifyForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = document.getElementById('verifyBtn');
        const alertEl = document.getElementById('alertVerify');
        alertEl.className = 'alert';

        btn.disabled = true;
        btn.textContent = 'Doğrulanıyor...';

        try {
            await Auth.verify(registeredEmail, document.getElementById('code').value);
            window.location.href = '/';
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Kod hatalı veya süresi dolmuş';
            alertEl.className = 'alert alert-error show';
            btn.disabled = false;
            btn.textContent = 'Doğrula';
        }
    });

    document.getElementById('resendLink').addEventListener('click', async (e) => {
        e.preventDefault();
        const alertEl = document.getElementById('alertVerify');
        try {
            await apiFetch('/auth/resend-code', {
                method: 'POST',
                body: JSON.stringify({ email: registeredEmail }),
            });
            alertEl.textContent = 'Kod tekrar gönderildi.';
            alertEl.className = 'alert alert-success show';
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Gönderim başarısız';
            alertEl.className = 'alert alert-error show';
        }
    });
