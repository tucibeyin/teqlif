import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';

final adDetailProvider =
    FutureProvider.family<AdModel, String>((ref, id) async {
  if (id.isEmpty || id.startsWith('channel:')) {
    throw StateError('No valid ad ID');
  }
  final res = await ApiClient().get(Endpoints.adById(id));
  return AdModel.fromJson(res.data as Map<String, dynamic>);
});
