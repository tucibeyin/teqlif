import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api/endpoints.dart';

/// Central error logger for the teqlif mobile app.
///
/// Sends errors to the backend /api/log-error endpoint (fire-and-forget).
/// Errors are written to fe_errors.log on VPS with "MOBILE" prefix.
///
/// Usage:
///   AppLogger.error('Something went wrong', error: e, stackTrace: st, context: 'MyScreen');
class AppLogger {
  AppLogger._();

  static String? _userId;

  /// Call this after login to attach user context to all future error logs.
  static void setUserId(String? id) {
    _userId = id;
  }

  /// Log an error. Never throws — safe to call from catch blocks.
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String context = 'Unknown',
  }) {
    // Always print to debug console
    if (kDebugMode) {
      debugPrint('[ERROR][$context] $message');
      if (error != null) debugPrint('  Error: $error');
      if (stackTrace != null) debugPrint('  Stack: $stackTrace');
    }

    // Fire-and-forget to backend
    _sendToBackend(message, error: error, stackTrace: stackTrace, context: context);
  }

  static void _sendToBackend(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String context = 'Unknown',
  }) {
    try {
      String fullMessage = '[MOBILE][$context] $message';
      String? stackStr;

      if (error != null) {
        fullMessage += ' | ${error.toString().substring(0, error.toString().length.clamp(0, 300))}';
      }
      if (stackTrace != null) {
        stackStr = stackTrace.toString().split('\n').take(5).join(' ');
      }

      final body = jsonEncode({
        'page': 'mobile/$context',
        'message': fullMessage.substring(0, fullMessage.length.clamp(0, 500)),
        'stack': stackStr,
        'userAgent': 'teqlifMobileApp/Flutter',
        'userId': _userId ?? 'anonymous',
      });

      http.post(
        Uri.parse('$kBaseUrl/api/log-error'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).catchError((_) {
        // Silence — never crash the app due to logging failure
      });
    } catch (_) {
      // Silence
    }
  }
}
