(function () {
    var toast = document.getElementById('proToast');
    var timer = null;

    function setPlan(type) {
        var isYearly = type === 'yearly';

        document.getElementById('btnMonthly').classList.toggle('active', !isYearly);
        document.getElementById('btnYearly').classList.toggle('active', isYearly);

        var periodEl   = document.getElementById('planPeriodLabel');
        var priceEl    = document.getElementById('planPrice');
        var subPriceEl = document.getElementById('planSubPrice');

        if (isYearly) {
            if (periodEl)   periodEl.textContent   = 'Yıllık';
            priceEl.textContent    = '₺4.800';
            subPriceEl.textContent = '≈ ₺400/ay · 2 ay bedava';
        } else {
            if (periodEl)   periodEl.textContent   = 'Aylık';
            priceEl.textContent    = '₺500';
            subPriceEl.textContent = '';
        }
    }

    document.getElementById('btnMonthly').addEventListener('click', function () { setPlan('monthly'); });
    document.getElementById('btnYearly').addEventListener('click',  function () { setPlan('yearly');  });

    document.getElementById('btnPro').addEventListener('click', function () {
        toast.classList.add('show');
        clearTimeout(timer);
        timer = setTimeout(function () { toast.classList.remove('show'); }, 4500);
    });
}());
