(function () {
  var IOS_STORE     = 'https://apps.apple.com/app/id6744777483';
  var ANDROID_STORE = 'https://play.google.com/store/apps/details?id=com.teqlif.teqlif_mobile';

  var ua        = navigator.userAgent || '';
  var isIOS     = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
  var isAndroid = /Android/i.test(ua);
  var isMobile  = isIOS || isAndroid;

  var storeUrl  = isIOS ? IOS_STORE : ANDROID_STORE;
  var btnOpen   = document.getElementById('btnOpen');
  var btnWeb    = document.getElementById('btnWeb');
  var appScheme = btnOpen ? btnOpen.getAttribute('data-scheme') : null;

  if (!isMobile) {
    window.location.replace(btnWeb.href);
    return;
  }

  btnOpen.textContent = isIOS ? 'Uygulamada Aç / App Store' : 'Uygulamada Aç / Play Store';

  // Sayfa yüklendiğinde otomatik olarak uygulamayı açmayı dene (bazı tarayıcılar engeller ama denemeye değer)
  if (appScheme && appScheme !== '') {
    setTimeout(function() {
      window.location.href = appScheme;
    }, 300);
  }

  btnOpen.addEventListener('click', function (e) {
    e.preventDefault();
    if (appScheme && appScheme !== '') {
      // Önce uygulamayı açmayı dene
      window.location.href = appScheme;
      // Uygulama yoksa 1.5 saniye sonra store'a at
      setTimeout(function() {
        window.location.href = storeUrl;
      }, 1500);
    } else {
      window.location.href = storeUrl;
    }
  });
})();
