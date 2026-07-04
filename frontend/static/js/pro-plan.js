(function () {
    var toast = document.getElementById('proToast');
    var timer = null;

    /* ── Fiyat toggle ───────────────────────────────────────── */
    function setPlan(type) {
        var isYearly = type === 'yearly';

        document.getElementById('btnMonthly').classList.toggle('active', !isYearly);
        document.getElementById('btnYearly').classList.toggle('active', isYearly);

        var cardMonthly = document.getElementById('cardMonthly');
        var cardYearly  = document.getElementById('cardYearly');
        if (cardMonthly) cardMonthly.classList.toggle('selected', !isYearly);
        if (cardYearly)  cardYearly.classList.toggle('selected',  isYearly);

        /* tfoot fiyat */
        var tfLabel = document.getElementById('tfootPriceLabel');
        var tfVal   = document.getElementById('tfootPriceVal');
        var tfSub   = document.getElementById('tfootPriceSub');

        if (isYearly) {
            if (tfLabel) tfLabel.textContent  = 'Yıllık';
            if (tfVal)   tfVal.textContent    = '₺1.990';
            if (tfSub)   tfSub.textContent    = '/ yıl · ~₺166/ay · 2 ay bedava';

            /* tablo: AI */
            document.querySelector('tr[data-key="ai"] .val-amount').textContent = '~₺1.200/yıl';
            document.querySelector('tr[data-key="ai"] .val-desc').innerHTML = '240 sorgu × 5 TUCi<br>= 1.200 TL tasarruf';

            /* tablo: boost */
            document.querySelector('tr[data-key="boost"] .td-std span').textContent = '0 adet / yıl';
            document.querySelector('tr[data-key="boost"] .td-pro span').textContent = '✔ 36 adet / yıl';
            document.querySelector('tr[data-key="boost"] .val-amount').textContent = '₺1.800/yıl';
            document.querySelector('tr[data-key="boost"] .val-desc').innerHTML = '36 boost × 50 TUCi<br>= 1.800 TL değer';

            /* tablo: blast */
            document.querySelector('tr[data-key="blast"] .td-std span').textContent = '36 adet / yıl · max 5 kişi';
            document.querySelector('tr[data-key="blast"] .td-pro span').textContent = '72 adet / yıl · max 10 kişi';
            document.querySelector('tr[data-key="blast"] .val-amount').textContent = '+36 Ekstra';
            document.querySelector('tr[data-key="blast"] .val-desc').innerHTML = '+36 ekstra ücretsiz duyuru hakkı (72/yıl) + 2× alıcı kapasitesi (10 kişi) · eksik hak için 10 TUCi/kişi';

            /* tfoot değer metni */
            var tfootValueText = document.getElementById('tfootValueText');
            if (tfootValueText) {
                tfootValueText.innerHTML = '₺1.990 yatır,<br><span style="color:var(--green);font-weight:700;">₺3.000+ değer</span><br><span style="color:var(--text-dim);font-size:.63rem;">1 TUCi = 1 TL</span>';
            }

            /* banner */
            var bannerText = document.getElementById('totalBannerText');
            if (bannerText) bannerText.innerHTML = '<strong>₺1.990 ödeyip ₺3.000+ değer elde et</strong><br><span style="color:var(--text-dim);font-size:.74rem;">Boost (₺1.800) + AI danışman (₺1.200) haklarını yıllık kullandığında maliyet kendini fazlasıyla karşılar.</span>';
            var totalVal = document.getElementById('totalVal');
            if (totalVal) totalVal.textContent = '₺3.000+';
            var totalSub = document.getElementById('totalSub');
            if (totalSub) totalSub.textContent = 'yıllık avantaj değeri';
            var roiPill = document.getElementById('roiPill');
            if (roiPill) roiPill.textContent = 'Maliyetin 1.5 katı değer 🎯';

        } else {
            if (tfLabel) tfLabel.textContent  = 'Aylık';
            if (tfVal)   tfVal.textContent    = '₺199';
            if (tfSub)   tfSub.textContent    = '/ ay · iptal istediğin an';

            /* tablo: AI */
            document.querySelector('tr[data-key="ai"] .val-amount').textContent = '~₺100/ay';
            document.querySelector('tr[data-key="ai"] .val-desc').innerHTML = '20 sorgu × 5 TUCi<br>= 100 TL tasarruf';

            /* tablo: boost */
            document.querySelector('tr[data-key="boost"] .td-std span').textContent = '0 adet / ay';
            document.querySelector('tr[data-key="boost"] .td-pro span').textContent = '✔ 3 adet / ay';
            document.querySelector('tr[data-key="boost"] .val-amount').textContent = '₺150/ay';
            document.querySelector('tr[data-key="boost"] .val-desc').innerHTML = '3 boost × 50 TUCi<br>= 150 TL değer';

            /* tablo: blast */
            document.querySelector('tr[data-key="blast"] .td-std span').textContent = '3 adet / ay · max 5 kişi';
            document.querySelector('tr[data-key="blast"] .td-pro span').textContent = '6 adet / ay · max 10 kişi';
            document.querySelector('tr[data-key="blast"] .val-amount').textContent = '+3 Ekstra';
            document.querySelector('tr[data-key="blast"] .val-desc').innerHTML = '+3 ekstra ücretsiz duyuru hakkı (6/ay) + 2× alıcı kapasitesi (10 kişi) · eksik hak için 10 TUCi/kişi';

            /* tfoot değer metni */
            var tfootValueText = document.getElementById('tfootValueText');
            if (tfootValueText) {
                tfootValueText.innerHTML = '₺199 yatır,<br><span style="color:var(--green);font-weight:700;">₺250+ değer</span><br><span style="color:var(--text-dim);font-size:.63rem;">1 TUCi = 1 TL</span>';
            }

            /* banner */
            var bannerText = document.getElementById('totalBannerText');
            if (bannerText) bannerText.innerHTML = '<strong>₺199 ödeyip ₺250+ değer elde et</strong><br><span style="color:var(--text-dim);font-size:.74rem;">Boost (₺150) + AI danışman (₺100) haklarını kullandığında her ay kazancın maliyetin karşılar.</span>';
            var totalVal = document.getElementById('totalVal');
            if (totalVal) totalVal.textContent = '₺250+';
            var totalSub = document.getElementById('totalSub');
            if (totalSub) totalSub.textContent = 'aylık avantaj değeri';
            var roiPill = document.getElementById('roiPill');
            if (roiPill) roiPill.textContent = 'Maliyetin karşılanır 🎯';
        }
    }

    document.getElementById('btnMonthly').addEventListener('click', function () { setPlan('monthly'); });
    document.getElementById('btnYearly').addEventListener('click',  function () { setPlan('yearly');  });

    /* Fiyat kartlarına da tıklanabilirlik */
    var cardM = document.getElementById('cardMonthly');
    var cardY = document.getElementById('cardYearly');
    if (cardM) cardM.addEventListener('click', function () { setPlan('monthly'); });
    if (cardY) cardY.addEventListener('click', function () { setPlan('yearly');  });

    /* ── Açılır satırlar ────────────────────────────────────── */
    document.querySelectorAll('tr.feat-row').forEach(function (row) {
        row.addEventListener('click', function () {
            var key     = row.dataset.key;
            var descRow = document.querySelector('tr.desc-row[data-key="' + key + '"]');
            var isOpen  = row.classList.contains('open');

            document.querySelectorAll('tr.feat-row.open').forEach(function (r) {
                r.classList.remove('open');
                var dk = r.dataset.key;
                var dr = document.querySelector('tr.desc-row[data-key="' + dk + '"]');
                if (dr) dr.classList.remove('open');
            });

            if (!isOpen) {
                row.classList.add('open');
                if (descRow) descRow.classList.add('open');
            }
        });
    });

    /* ── Pro butonu ─────────────────────────────────────────── */
    document.getElementById('btnPro').addEventListener('click', function () {
        toast.classList.add('show');
        clearTimeout(timer);
        timer = setTimeout(function () { toast.classList.remove('show'); }, 4500);
    });
}());
