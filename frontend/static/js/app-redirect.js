/**
 * teqlif — Akıllı Uygulama Yönlendirme
 *
 * Mobil ziyaretçiye "Uygulamada Aç" banner'ı gösterir.
 * - Uygulama kuruluysa: teqlif:// custom scheme ile açar
 * - Kurulu değilse: 1.5s sonra App Store / Play Store'a yönlendirir
 *
 * Kullanım: teqlifAppRedirect('yayin/123')
 *           teqlifAppRedirect('profil/username')
 *           teqlifAppRedirect('ilan/456')
 */

(function () {
  var IOS_STORE     = 'https://apps.apple.com/tr/app/teqlif/id6744777483';
  var ANDROID_STORE = 'https://play.google.com/store/apps/details?id=com.teqlif.teqlif_mobile';
  var SCHEME        = 'teqlif';
  var DISMISS_KEY   = 'teqlif_app_banner_dismissed';

  var ua        = navigator.userAgent || '';
  var isIOS     = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
  var isAndroid = /Android/i.test(ua);
  var isMobile  = isIOS || isAndroid;

  function storeUrl() {
    return isIOS ? IOS_STORE : ANDROID_STORE;
  }

  /**
   * Uygulamayı custom scheme ile açmayı dener.
   * 1.5s içinde açılmazsa store'a yönlendirir.
   */
  function openApp(deepPath) {
    var schemeUrl = SCHEME + '://' + deepPath;
    var left = true;

    // Sayfa gizlenince (uygulama açıldı) yönlendirmeyi iptal et
    document.addEventListener('visibilitychange', function onVis() {
      if (document.hidden) {
        left = false;
        document.removeEventListener('visibilitychange', onVis);
      }
    });

    window.location = schemeUrl;

    setTimeout(function () {
      if (left && !document.hidden) {
        window.location = storeUrl();
      }
    }, 1500);
  }

  /**
   * Sayfanın üstüne "Uygulamada Aç" banner'ı enjekte eder.
   * Daha önce kapatıldıysa göstermez.
   */
  function showBanner(deepPath) {
    if (!isMobile) return;
    if (sessionStorage.getItem(DISMISS_KEY)) return;

    var banner = document.createElement('div');
    banner.id = 'teqlif-app-banner';
    banner.style.cssText = [
      'position:fixed',
      'top:0',
      'left:0',
      'right:0',
      'z-index:99999',
      'background:#0f172a',
      'color:#fff',
      'display:flex',
      'align-items:center',
      'padding:10px 14px',
      'gap:10px',
      'box-shadow:0 2px 12px rgba(0,0,0,.45)',
      'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif',
      'font-size:14px',
    ].join(';');

    banner.innerHTML =
      '<img src="/static/icons/icon-192.png" style="width:40px;height:40px;border-radius:10px;flex-shrink:0" alt="teqlif">' +
      '<div style="flex:1;min-width:0">' +
        '<div style="font-weight:700;font-size:15px">teqlif</div>' +
        '<div style="color:#94a3b8;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' +
          (isIOS ? 'App Store\'da ücretsiz' : 'Google Play\'de ücretsiz') +
        '</div>' +
      '</div>' +
      '<button id="teqlif-open-btn" style="' +
        'background:#06b6d4;color:#fff;border:none;border-radius:20px;' +
        'padding:8px 18px;font-size:13px;font-weight:700;cursor:pointer;flex-shrink:0' +
      '">Aç</button>' +
      '<button id="teqlif-close-btn" style="' +
        'background:none;border:none;color:#94a3b8;font-size:20px;cursor:pointer;' +
        'padding:0 4px;line-height:1;flex-shrink:0' +
      '">×</button>';

    document.body.insertBefore(banner, document.body.firstChild);

    // Banner yüksekliği kadar içeriği aşağı kaydır
    var h = banner.offsetHeight || 64;
    document.body.style.paddingTop = (parseInt(document.body.style.paddingTop || '0', 10) + h) + 'px';

    document.getElementById('teqlif-open-btn').addEventListener('click', function () {
      openApp(deepPath);
    });

    document.getElementById('teqlif-close-btn').addEventListener('click', function () {
      sessionStorage.setItem(DISMISS_KEY, '1');
      banner.remove();
      document.body.style.paddingTop = '';
    });
  }

  // Public API
  window.teqlifAppRedirect = function (deepPath) {
    if (!isMobile) return;
    showBanner(deepPath);
  };
})();
