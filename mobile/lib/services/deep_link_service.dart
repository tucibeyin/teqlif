import 'package:app_links/app_links.dart';
import 'storage_service.dart';

/// Deep link koordinatörü.
///
/// - Splash cold-start URI'yi kaydeder, MainScreen tüketir.
/// - Aynı URI'nin kısa sürede tekrar işlenmesini önler (WhatsApp IAB gibi
///   durumlarda teqlif:// birden fazla kez ateşlenebilir).
class DeepLinkService {
  DeepLinkService._();

  static Uri? _pendingUri;

  // Deduplication: aynı URI 4 saniye içinde tekrar gelirse yoksay
  static String? _lastHandledKey;
  static DateTime? _lastHandledAt;
  static const _dedupWindow = Duration(seconds: 30);

  /// Splash ekranı tarafından cold-start anında set edilir.
  static void setPending(Uri uri) => _pendingUri = uri;

  /// MainScreen tarafından bir kez okunur; sonraki çağrılarda null döner.
  static Uri? consumePending() {
    final uri = _pendingUri;
    _pendingUri = null;
    return uri;
  }

  /// Aynı URI kısa sürede tekrar gelirse false döner (duplicate).
  ///
  /// `https://www.teqlif.com/yayin/529` ile `teqlif://yayin/529` aynı
  /// içeriği temsil eder — scheme/host farkına rağmen duplicate sayılır.
  static bool shouldHandle(Uri uri) {
    final key = _contentKey(uri);
    final now = DateTime.now();
    if (_lastHandledKey == key &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < _dedupWindow) {
      return false;
    }
    _lastHandledKey = key;
    _lastHandledAt = now;
    return true;
  }

  /// URI'den scheme/host bağımsız içerik anahtarı üretir.
  static String _contentKey(Uri uri) {
    final segs = _getNormalizedSegments(uri);
    if (segs.length >= 2) return '${segs[0]}/${segs[1]}';
    if (segs.isNotEmpty) return segs[0];
    return uri.toString();
  }

  /// Custom scheme (teqlif://) ve HTTPS (https://) linkleri için path'leri standartlaştırır.
  /// https://teqlif.com/invite -> ['invite']
  /// teqlif://invite -> ['invite']
  /// teqlif://ilan/55 -> ['ilan', '55']
  static List<String> _getNormalizedSegments(Uri uri) {
    if (uri.scheme == 'teqlif') {
      final host = uri.host;
      final paths = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return [if (host.isNotEmpty) host, ...paths];
    }
    return uri.pathSegments.where((s) => s.isNotEmpty).toList();
  }

  /// Cold-start linkini okur ve kaydeder. SplashScreen'den çağrılır.
  /// Davet linki ise kodu SharedPreferences'a yazar (auth akışından önce).
  static Future<void> captureInitialLink() async {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (uri != null) {
      setPending(uri);
      final code = extractInviteCode(uri);
      if (code != null) {
        await StorageService.savePendingReferralCode(code);
      }
    }
  }

  /// Canlı URI stream'i — MainScreen subscribe olur.
  static Stream<Uri> get uriStream => AppLinks().uriLinkStream;

  /// https://teqlif.com/invite?code=TQLF8X2 veya teqlif://invite?code=TQLF8X2 linkinden kodu çıkarır.
  /// Davet linki değilse null döner.
  static String? extractInviteCode(Uri uri) {
    final segs = _getNormalizedSegments(uri);
    if (segs.isEmpty || segs.first != 'invite') return null;
    return uri.queryParameters['code'];
  }
}
