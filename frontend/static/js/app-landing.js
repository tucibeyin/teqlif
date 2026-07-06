(function () {
  var IOS_STORE     = 'https://apps.apple.com/app/id6744777483';
  var ANDROID_STORE = 'https://play.google.com/store/apps/details?id=com.teqlif.teqlif_mobile';

  var ua        = navigator.userAgent || '';
  var isIOS     = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
  var isAndroid = /Android/i.test(ua);
  var isMobile  = isIOS || isAndroid;

  var storeUrl  = isIOS ? IOS_STORE : ANDROID_STORE;
  var btnOpen   = document.getElementById('btnOpen');
  var btnStore  = document.getElementById('btnStore');
  var btnWeb    = document.getElementById('btnWeb');
  var appScheme = btnOpen ? btnOpen.getAttribute('data-scheme') : null;

  if (!isMobile) {
    window.location.replace(btnWeb.href);
    return;
  }

  btnStore.textContent = isIOS ? 'App Store\'dan İndir' : 'Play Store\'dan İndir';

  // Sayfa yüklendiğinde otomatik olarak uygulamayı açmayı dene
  if (appScheme && appScheme !== '') {
    setTimeout(function() {
      window.location.href = appScheme;
    }, 300);
  }

  // "Uygulamayı Aç" Butonu
  btnOpen.addEventListener('click', function (e) {
    e.preventDefault();
    if (appScheme && appScheme !== '') {
      window.location.href = appScheme;
    }
  });

  // "Mağazadan İndir" Butonu
  btnStore.addEventListener('click', function (e) {
    e.preventDefault();
    window.location.href = storeUrl;
  });
})();
