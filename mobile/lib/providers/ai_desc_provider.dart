import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

enum AiDescStatus { idle, loading, done, error }

class AiDescState {
  final AiDescStatus status;
  final String text;
  final String provider;
  final int tuciSpent;

  const AiDescState({
    this.status = AiDescStatus.idle,
    this.text = '',
    this.provider = '',
    this.tuciSpent = 0,
  });
}

class AiDescNotifier extends StateNotifier<AiDescState> {
  AiDescNotifier() : super(const AiDescState());

  Future<void> generate({
    required String title,
    required String category,
    required String? condition,
    required double? price,
    required String? subcategory,
    required Map<String, dynamic> extraFields,
    required String lang,
  }) async {
    state = const AiDescState(status: AiDescStatus.loading);
    try {
      final token = await StorageService.getToken();
      final data = await apiCall(() => http.post(
            Uri.parse('$kBaseUrl/listings/generate-description'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'title': title,
              'category': category,
              'condition': condition,
              'lang': lang,
              if (price != null && price > 0) 'price': price,
              'subcategory': ?subcategory,
              if (extraFields.isNotEmpty) 'extra_fields': extraFields,
            }),
          ));

      final text = data['description'] as String? ?? '';
      final provider = data['provider'] as String? ?? '';
      final tuciSpent = (data['tuci_spent'] as num?)?.toInt() ?? 0;

      if (tuciSpent > 0) {
        CacheService.clearData('user_wallet_data');
      }

      state = AiDescState(
        status: AiDescStatus.done,
        text: text,
        provider: provider,
        tuciSpent: tuciSpent,
      );
    } catch (e) {
      state = const AiDescState(status: AiDescStatus.error);
      rethrow;
    }
  }

  void reset() => state = const AiDescState();
}

final aiDescProvider =
    StateNotifierProvider.autoDispose<AiDescNotifier, AiDescState>(
  (ref) => AiDescNotifier(),
);
