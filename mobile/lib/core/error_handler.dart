import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'event_bus.dart';

class TeqlifException implements Exception {
  final String code;
  final String message;
  final String? requestId;

  TeqlifException({required this.code, required this.message, this.requestId});

  factory TeqlifException.fromJson(Map<String, dynamic> json) {
    return TeqlifException(
      code: json['code'] ?? 'UNKNOWN_ERROR',
      message: json['message'] ?? 'Beklenmeyen bir hata oluştu.',
      requestId: json['request_id'],
    );
  }

  @override
  String toString() => message;
}

class ErrorHandler {
  /// DioException veya standart Exception'ları yakalayıp TeqlifException'a çevirir.
  static TeqlifException parseError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data != null && error.response?.data is Map) {
        final data = error.response!.data as Map<String, dynamic>;
        if (data.containsKey('error')) {
          final teqlifErr = TeqlifException.fromJson(data['error']);
          
          // Global event tetiklemeleri
          if (teqlifErr.code == 'UNAUTHORIZED' || teqlifErr.code == 'HTTP_401') {
            eventBus.fire(AuthErrorEvent(teqlifErr.message));
          } else if (teqlifErr.code == 'VALIDATION_ERROR') {
            eventBus.fire(ValidationErrorEvent(data['error']['details'] ?? {}));
          }
          return teqlifErr;
        }
      }
      return TeqlifException(
        code: 'NETWORK_ERROR',
        message: 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.',
      );
    }
    
    return TeqlifException(
      code: 'APP_ERROR',
      message: error.toString(),
    );
  }

  /// UI seviyesinde yakalanan hataları kullanıcıya gösterir.
  static void showSnackBar(BuildContext context, dynamic error) {
    final teqlifError = parseError(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(teqlifError.message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
