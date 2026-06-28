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
            
            document.querySelector('tr[data-key="ai"] .val-amount').textContent = '~₺1.200/yıl';
            document.querySelector('tr[data-key="ai"] .val-desc').innerHTML = '240 kullanım × 5 TUCi<br>= 1.200 TL tasarruf';
            
            document.querySelector('tr[data-key="boost"] .val-amount').textContent = '₺12.000/yıl';
            document.querySelector('tr[data-key="boost"] .val-desc').innerHTML = '240 boost × 50 TUCi<br>= 12.000 TL değer';
            
            document.querySelector('tr[data-key="blast"] .val-amount').textContent = '~₺1.020/yıl';
            document.querySelector('tr[data-key="blast"] .val-desc').innerHTML = '+204 ekstra blast × 5 TUCi<br>= 1.020 TL tasarruf';
            
            document.querySelector('.tfoot-val-num').textContent = '₺14.220+';
            document.querySelector('.tfoot-val-sub').textContent = 'yıllık avantaj değeri (hesaplanabilir)';
            
            document.querySelector('.tfoot-val > div').innerHTML = '₺2.000 yatır,<br><span style="color:var(--green);font-weight:700;">₺14.220+ kazan.</span><br><span style="color:var(--text-dim);font-size:.63rem;">1 TUCi = 1 TL</span>';
            
            document.querySelector('.total-banner-text > span').innerHTML = 'Boost ve blast haklarınızı kullandığınızda ₺2.000 ödeyip <strong style="color:var(--green)">₺14.220+ değer</strong> elde edersiniz.';
            document.querySelector('.total-val').textContent = '₺14.220+';
            document.querySelector('.total-sub').textContent = 'yıllık avantaj değeri';
        } else {
            periodEl.textContent   = 'Aylık';
            priceEl.textContent    = '₺200';
            subPriceEl.textContent = '';
            
            document.querySelector('tr[data-key="ai"] .val-amount').textContent = '~₺100/ay';
            document.querySelector('tr[data-key="ai"] .val-desc').innerHTML = '20 kullanım × 5 TUCi<br>= 100 TL tasarruf';
            
            document.querySelector('tr[data-key="boost"] .val-amount').textContent = '₺1.000/ay';
            document.querySelector('tr[data-key="boost"] .val-desc').innerHTML = '20 boost × 50 TUCi<br>= 1.000 TL değer';
            
            document.querySelector('tr[data-key="blast"] .val-amount').textContent = '~₺85/ay';
            document.querySelector('tr[data-key="blast"] .val-desc').innerHTML = '+17 ekstra blast × 5 TUCi<br>= 85 TL tasarruf';
            
            document.querySelector('.tfoot-val-num').textContent = '₺1.185+';
            document.querySelector('.tfoot-val-sub').textContent = 'aylık avantaj değeri (hesaplanabilir)';
            
            document.querySelector('.tfoot-val > div').innerHTML = '₺200 yatır,<br><span style="color:var(--green);font-weight:700;">₺1.185+ kazan.</span><br><span style="color:var(--text-dim);font-size:.63rem;">1 TUCi = 1 TL</span>';
            
            document.querySelector('.total-banner-text > span').innerHTML = 'Boost ve blast haklarınızı kullandığınızda ₺200 ödeyip <strong style="color:var(--green)">₺1.185+ değer</strong> elde edersiniz.';
            document.querySelector('.total-val').textContent = '₺1.185+';
            document.querySelector('.total-sub').textContent = 'aylık avantaj değeri';
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
