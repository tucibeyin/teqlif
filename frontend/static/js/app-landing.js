(function () {
  var IOS_STORE     = 'https://apps.apple.com/app/id6744777483';
  var ANDROID_STORE = 'https://play.google.com/store/apps/details?id=com.teqlif.teqlif_mobile';

  var ua        = navigator.userAgent || '';
  var isIOS     = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
  var isAndroid = /Android/i.test(ua);
  var isMobile  = isIOS || isAndroid;

  var storeUrl = isIOS ? IOS_STORE : ANDROID_STORE;
  var btnOpen  = document.getElementById('btnOpen');
  var btnWeb   = document.getElementById('btnWeb');

  if (!isMobile) {
    window.location.replace(btnWeb.href);
    return;
  }

  btnOpen.textContent = isIOS ? 'App Store\'dan İndir' : 'Play Store\'dan İndir';

  btnOpen.addEventListener('click', function (e) {
    e.preventDefault();
    window.location.href = storeUrl;
  });
})();
