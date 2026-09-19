import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppConfig {
  final String baseHost;
  final String baseUrl;
  final String mediaBaseUrl;

  AppConfig._({
    required this.baseHost,
    required this.baseUrl,
    required this.mediaBaseUrl,
  });

  factory AppConfig.fromEnvironment() {
    const host = String.fromEnvironment('BASE_HOST');
    if (host.isEmpty) {
      throw AssertionError(
        'BASE_HOST is not defined! Please run with --dart-define-from-file=dart_defines/staging.json or release.json',
      );
    }
    
    // api.teqlif.com -> www.teqlif.com
    // api-staging.teqlif.com -> staging.teqlif.com
    String mediaHost = host.replaceAll('api-staging.', 'staging.').replaceAll('api.', 'www.');
    
    return AppConfig._(
      baseHost: host,
      baseUrl: '$host/api',
      mediaBaseUrl: mediaHost,
    );
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());
