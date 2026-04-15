import 'package:app_links/app_links.dart';

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
  static const _dedupWindow = Duration(seconds: 4);

  /// Splash ekranı tarafından cold-start anında set edilir.
  static void setPending(Uri uri) => _pendingUri = uri;

  /// MainScreen tarafından bir kez okunur; sonraki çağrılarda null döner.
  static Uri? consumePending() {
    final uri = _pendingUri;
    _pendingUri = null;
    return uri;
  }

  /// Aynı URI kısa sürede tekrar gelirse false döner (duplicate).
  static bool shouldHandle(Uri uri) {
    final key = uri.toString();
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

  /// Cold-start linkini okur ve kaydeder. SplashScreen'den çağrılır.
  static Future<void> captureInitialLink() async {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (uri != null) setPending(uri);
  }

  /// Canlı URI stream'i — MainScreen subscribe olur.
  static Stream<Uri> get uriStream => AppLinks().uriLinkStream;
}
