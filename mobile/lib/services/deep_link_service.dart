import 'package:app_links/app_links.dart';

/// Deep link koordinatörü.
///
/// Splash ekranı cold-start URI'yi buraya yazar.
/// MainScreen başlarken okur ve sıfırlar — tek kullanım garantisi.
class DeepLinkService {
  DeepLinkService._();

  static Uri? _pendingUri;

  /// Splash ekranı tarafından cold-start anında set edilir.
  static void setPending(Uri uri) => _pendingUri = uri;

  /// MainScreen tarafından bir kez okunur; sonraki çağrılarda null döner.
  static Uri? consumePending() {
    final uri = _pendingUri;
    _pendingUri = null;
    return uri;
  }

  /// Cold-start linkini okur ve [DeepLinkService.setPending] ile kaydeder.
  /// SplashScreen'den çağrılır.
  static Future<void> captureInitialLink() async {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (uri != null) setPending(uri);
  }

  /// Canlı URI stream'i — MainScreen subscribe olur.
  static Stream<Uri> get uriStream => AppLinks().uriLinkStream;
}
