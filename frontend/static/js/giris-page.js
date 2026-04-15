    const _nextUrl = new URLSearchParams(location.search).get('next') || '/';
    if (Auth.getToken()) { window.location.href = _nextUrl; }
    else if (Auth.getUser()) {
        // Kullanıcı adı localStorage'da var ama token yok → oturum sona ermiş.
        // Refresh cookie hâlâ geçerliyse sessizce yenile ve devam et.
        Auth.tryRefresh().then(ok => { if (ok) window.location.href = _nextUrl; });
    }

    document.getElementById('loginForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = document.getElementById('submitBtn');
        const alertEl = document.getElementById('alert');
        alertEl.className = 'alert';

        btn.disabled = true;
        btn.textContent = 'Giriş yapılıyor...';

        try {
            await Auth.login(
                document.getElementById('email').value,
                document.getElementById('password').value
            );
            window.location.href = _nextUrl;
        } catch (err) {
            if (err.error?.code === 'EMAIL_NOT_VERIFIED') {
                const email = document.getElementById('email').value.trim();
                try {
                    await apiFetch('/auth/resend-code', {
                        method: 'POST',
                        body: JSON.stringify({ email }),
                    });
                } catch (_) {}
                window.location.href = '/kayit.html?email=' + encodeURIComponent(email) + '&verify=1';
                return;
            }
            alertEl.textContent = err.error?.message || 'Bir hata oluştu';
            alertEl.className = 'alert alert-error show';
            btn.disabled = false;
            btn.textContent = 'Giriş Yap';
        }
    });
