import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/notification.dart';
import '../../../core/providers/auth_provider.dart';

final notificationsProvider =
    FutureProvider<List<NotificationModel>>((ref) async {
  ref.watch(authProvider); // Rebuild provider on auth state changes
  final res = await ApiClient().get(Endpoints.notifications);
  final data = res.data;
  final list = (data['notifications'] ?? data) as List<dynamic>;
  return list
      .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
