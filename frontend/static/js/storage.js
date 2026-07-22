// Safe localStorage wrapper — Safari Private Mode, ITP, SecurityError koruması.
// Tüm JS dosyaları localStorage yerine window._storage kullanır.
// Bu script diğer tüm script'lerden ÖNCE yüklenmelidir.
window._storage = (function () {
    try {
        var _TEST = '__teqlif_s__';
        localStorage.setItem(_TEST, '1');
        localStorage.removeItem(_TEST);
        return localStorage;
    } catch (_) {
        // Safari Private Browsing, ITP, veya SecurityError — in-memory fallback
        var _m = Object.create(null);
        return {
            getItem:    function (k) { return Object.prototype.hasOwnProperty.call(_m, k) ? _m[k] : null; },
            setItem:    function (k, v) { _m[k] = String(v); },
            removeItem: function (k) { delete _m[k]; },
            clear:      function () { _m = Object.create(null); },
            key:        function (i) { return Object.keys(_m)[i] || null; },
            get length() { return Object.keys(_m).length; }
        };
    }
}());
