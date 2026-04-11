    // Giriş yapılmamışsa yönlendir
    (function () {
        const token = localStorage.getItem('teqlif_token');
        if (!token) {
            window.location.href = '/giris.html?next=/ilan-ver.html';
        }
    })();

    // --- Photo management ---
    const MAX_PHOTOS = 10;
    let selectedFiles = []; // {file, objectUrl}

    const photoInput = document.getElementById('photoInput');
    const photoPreviews = document.getElementById('photoPreviews');
    const photoCount = document.getElementById('photoCount');
    const photoDrop = document.getElementById('photoDrop');

    photoInput.addEventListener('change', (e) => addFiles(Array.from(e.target.files)));
    photoInput.addEventListener('click', (e) => e.stopPropagation());

    // Drag & drop
    photoDrop.addEventListener('dragover', (e) => { e.preventDefault(); photoDrop.style.borderColor = 'var(--primary, #06b6d4)'; });
    photoDrop.addEventListener('dragleave', () => { photoDrop.style.borderColor = ''; });
    photoDrop.addEventListener('drop', (e) => {
        e.preventDefault();
        photoDrop.style.borderColor = '';
        addFiles(Array.from(e.dataTransfer.files).filter(f => f.type.startsWith('image/')));
    });

    function addFiles(files) {
        const remaining = MAX_PHOTOS - selectedFiles.length;
        if (remaining <= 0) return;
        const toAdd = files.slice(0, remaining);
        toAdd.forEach(f => {
            selectedFiles.push({ file: f, objectUrl: URL.createObjectURL(f) });
        });
        renderPreviews();
        // Reset input so same file can be re-added after removal
        photoInput.value = '';
    }

    function removeFile(idx) {
        URL.revokeObjectURL(selectedFiles[idx].objectUrl);
        selectedFiles.splice(idx, 1);
        renderPreviews();
    }

    function renderPreviews() {
        photoPreviews.innerHTML = '';
        selectedFiles.forEach(({ objectUrl }, i) => {
            const wrap = document.createElement('div');
            wrap.className = 'photo-thumb';

            const img = document.createElement('img');
            img.src = objectUrl;
            wrap.appendChild(img);

            if (i === 0) {
                const badge = document.createElement('span');
                badge.className = 'cover-badge';
                badge.textContent = 'Kapak';
                wrap.appendChild(badge);
            }

            const btn = document.createElement('button');
            btn.className = 'remove-btn';
            btn.type = 'button';
            btn.textContent = '✕';
            btn.onclick = () => removeFile(i);
            wrap.appendChild(btn);

            photoPreviews.appendChild(wrap);
        });

        const count = selectedFiles.length;
        photoCount.textContent = count > 0 ? `${count} fotoğraf seçildi` : '';
    }

    // Upload a single file, returns URL string or null
    async function uploadFile(file, token) {
        const fd = new FormData();
        fd.append('file', file);
        const res = await fetch('/api/upload', {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${token}` },
            body: fd,
        });
        if (!res.ok) return null;
        const data = await res.json();
        return data.url || null;
    }

    // Kategorileri API'den çek
    async function loadCategories() {
        try {
            const cats = await apiFetch('/categories');
            const sel = document.getElementById('category');
            cats.forEach(c => {
                const opt = document.createElement('option');
                opt.value = c.key;
                opt.textContent = c.label;
                sel.appendChild(opt);
            });
        } catch (_) {
            // Fallback
            const fallback = [
                ['elektronik', '📱 Elektronik'],
                ['vasita', '🚗 Vasıta'],
                ['emlak', '🏠 Emlak'],
                ['giyim', '👗 Giyim'],
                ['spor', '⚽ Spor'],
                ['kitap', '📚 Kitap & Müzik'],
                ['ev', '🛋 Ev & Bahçe'],
                ['diger', '📦 Diğer'],
            ];
            const sel = document.getElementById('category');
            fallback.forEach(([k, l]) => {
                const opt = document.createElement('option');
                opt.value = k;
                opt.textContent = l;
                sel.appendChild(opt);
            });
        }
    }

    function showAlert(msg, type) {
        const el = document.getElementById('alertMsg');
        el.textContent = msg;
        el.className = 'alert-msg ' + type;
        el.style.display = 'block';
        el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }

    async function submitForm(e) {
        e.preventDefault();
        const btn = document.getElementById('submitBtn');
        btn.disabled = true;
        btn.textContent = 'Yayınlanıyor...';
        document.getElementById('alertMsg').style.display = 'none';

        const title = document.getElementById('title').value.trim();
        const category = document.getElementById('category').value;
        const price = parseFloat(document.getElementById('price').value.replace(/\./g, '').replace(',', '.'));
        const location = document.getElementById('location').value.trim() || null;
        const description = document.getElementById('description').value.trim();

        const token = localStorage.getItem('teqlif_token');

        try {
            // Upload photos
            const imageUrls = [];
            if (selectedFiles.length > 0) {
                const progressWrap = document.getElementById('progressWrap');
                const progressBar = document.getElementById('progressBar');
                progressWrap.style.display = 'block';

                for (let i = 0; i < selectedFiles.length; i++) {
                    const url = await uploadFile(selectedFiles[i].file, token);
                    if (url) imageUrls.push(url);
                    progressBar.style.width = `${Math.round(((i + 1) / selectedFiles.length) * 100)}%`;
                }
                progressWrap.style.display = 'none';
            }

            const captchaToken = await getCaptchaToken();
            await apiFetch('/listings', {
                method: 'POST',
                body: JSON.stringify({
                    title, category, price, location, description,
                    image_urls: imageUrls,
                    ...(imageUrls.length > 0 ? { image_url: imageUrls[0] } : {}),
                }),
                headers: captchaToken ? { 'X-Captcha-Token': captchaToken } : {},
            });
            showAlert('İlanınız başarıyla yayına alındı!', 'success');
            document.getElementById('ilanForm').reset();
            selectedFiles = [];
            renderPreviews();
            setTimeout(() => window.location.href = '/?tab=ilanlar', 1500);
        } catch (err) {
            const errCode = err?.error?.code;
            if (errCode === 'RATE_LIMIT_EXCEEDED') {
                showAlert('Çok hızlı işlem yapıyorsunuz. Lütfen biraz bekleyin.', 'error');
            } else if (errCode === 'FORBIDDEN' || err?.error?.status === 403) {
                showAlert('Güvenlik doğrulaması başarısız. Lütfen tekrar deneyin.', 'error');
            } else {
                showAlert(err?.error?.message || 'Bir hata oluştu, lütfen tekrar deneyin.', 'error');
            }
        } finally {
            btn.disabled = false;
            btn.textContent = 'İlanı Yayınla';
        }
    }

    // Price formatter: 1000000 → 1.000.000
    (function () {
        const input = document.getElementById('price');
        input.addEventListener('input', function () {
            let raw = this.value.replace(/[^\d,]/g, ''); // sadece rakam ve virgül
            // Virgülden sonraki kısmı ayır
            const parts = raw.split(',');
            const intPart = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, '.');
            this.value = parts.length > 1
                ? intPart + ',' + parts[1].slice(0, 2)
                : intPart;
        });
    })();

    async function loadCities() {
        try {
            const cities = await apiFetch('/cities');
            const sel = document.getElementById('location');
            cities.forEach(c => {
                const opt = document.createElement('option');
                opt.value = c;
                opt.textContent = c;
                sel.appendChild(opt);
            });
        } catch (_) { }
    }

    loadCategories();
    loadCities();
