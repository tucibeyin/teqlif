(function () {
    var toast = document.getElementById('proToast');
    var timer = null;

    function setPlan(type) {
        var isYearly = type === 'yearly';

        document.getElementById('btnMonthly').classList.toggle('active', !isYearly);
        document.getElementById('btnYearly').classList.toggle('active', isYearly);

        var priceEl    = document.getElementById('planPrice');
        var subPriceEl = document.getElementById('planSubPrice');
        if (isYearly) {
            priceEl.textContent    = '4.800 TUCi / yıl';
            subPriceEl.textContent = '≈ 400 TUCi/ay · 2 ay bedava';
        } else {
            priceEl.textContent    = '500 TUCi / ay';
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
