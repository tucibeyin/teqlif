import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';

final liveStreamsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient().get(Endpoints.liveStreams);
  final data = res.data as Map<String, dynamic>? ?? {};
  final list = data['streams'] as List<dynamic>? ?? [];
  return list.cast<Map<String, dynamic>>();
});
