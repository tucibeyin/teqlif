    if (Auth.getToken() || Auth.getUser()) {
        Auth.tryRefresh().then(ok => { if (ok) window.location.href = '/'; });
    }

    let _resetEmail = '';

    document.getElementById('emailForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = document.getElementById('emailBtn');
        const alertEl = document.getElementById('alertEmail');
        alertEl.className = 'alert';

        btn.disabled = true;
        btn.textContent = 'Gönderiliyor...';

        try {
            _resetEmail = document.getElementById('email').value.trim();
            await Auth.forgotPassword(_resetEmail);

            document.getElementById('stepEmail').style.display = 'none';
            document.getElementById('stepReset').style.display = 'block';
            document.getElementById('resetSubtitle').textContent =
                _resetEmail + ' adresine 6 haneli sıfırlama kodu gönderdik.';
            document.getElementById('code').focus();
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Bir hata oluştu';
            alertEl.className = 'alert alert-error show';
            btn.disabled = false;
            btn.textContent = 'Kod Gönder';
        }
    });

    document.getElementById('resetForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = document.getElementById('resetBtn');
        const alertEl = document.getElementById('alertReset');
        alertEl.className = 'alert';

        const newPassword = document.getElementById('newPassword').value;
        const confirm = document.getElementById('newPasswordConfirm').value;

        if (newPassword !== confirm) {
            alertEl.textContent = 'Şifreler eşleşmiyor';
            alertEl.className = 'alert alert-error show';
            return;
        }
        if (newPassword.length < 8) {
            alertEl.textContent = 'Şifre en az 8 karakter olmalı';
            alertEl.className = 'alert alert-error show';
            return;
        }

        btn.disabled = true;
        btn.textContent = 'Güncelleniyor...';

        try {
            await Auth.resetPassword(
                _resetEmail,
                document.getElementById('code').value.trim(),
                newPassword,
            );
            window.location.href = '/giris.html?reset=1';
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Kod hatalı veya süresi dolmuş';
            alertEl.className = 'alert alert-error show';
            btn.disabled = false;
            btn.textContent = 'Şifreyi Güncelle';
        }
    });

    document.getElementById('resendLink').addEventListener('click', async (e) => {
        e.preventDefault();
        const alertEl = document.getElementById('alertReset');
        try {
            await Auth.forgotPassword(_resetEmail);
            alertEl.textContent = 'Kod tekrar gönderildi.';
            alertEl.className = 'alert alert-success show';
        } catch (err) {
            alertEl.textContent = err.error?.message || 'Gönderim başarısız';
            alertEl.className = 'alert alert-error show';
        }
    });
