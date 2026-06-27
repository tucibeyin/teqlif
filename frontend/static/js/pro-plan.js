(function () {
    var toast = document.getElementById('proToast');
    var timer = null;

    /* ── Fiyat toggle ───────────────────────────────────────── */
    function setPlan(type) {
        var isYearly = type === 'yearly';

        document.getElementById('btnMonthly').classList.toggle('active', !isYearly);
        document.getElementById('btnYearly').classList.toggle('active', isYearly);

        var periodEl   = document.getElementById('planPeriodLabel');
        var priceEl    = document.getElementById('planPrice');
        var subPriceEl = document.getElementById('planSubPrice');

        if (isYearly) {
            periodEl.textContent   = 'Yıllık';
            priceEl.textContent    = '₺2.000';
            subPriceEl.textContent = '≈ ₺167/ay · 2 ay bedava';
        } else {
            periodEl.textContent   = 'Aylık';
            priceEl.textContent    = '₺200';
            subPriceEl.textContent = '';
        }
    }

    document.getElementById('btnMonthly').addEventListener('click', function () { setPlan('monthly'); });
    document.getElementById('btnYearly').addEventListener('click',  function () { setPlan('yearly');  });

    /* ── Açılır satırlar ────────────────────────────────────── */
    document.querySelectorAll('tr.feat-row').forEach(function (row) {
        row.addEventListener('click', function () {
            var key     = row.dataset.key;
            var descRow = document.querySelector('tr.desc-row[data-key="' + key + '"]');
            var isOpen  = row.classList.contains('open');

            // Diğer açık satırları kapat
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
