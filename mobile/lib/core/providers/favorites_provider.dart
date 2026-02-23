import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/ad.dart';

final favoritesProvider = FutureProvider<List<AdModel>>((ref) async {
  final res = await ApiClient().get(Endpoints.favorites);
  final list = res.data as List<dynamic>;
  return list.map((e) => AdModel.fromJson(e as Map<String, dynamic>)).toList();
});
