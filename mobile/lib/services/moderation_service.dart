import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import 'storage_service.dart';

class ModerationService {
  final ApiClient _api;
  ModerationService(this._api);

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: true);
  }

  Future<void> mute(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/moderation/$streamId/mute'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  Future<void> unmute(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/moderation/$streamId/unmute'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  Future<void> kick(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/moderation/$streamId/kick'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  Future<void> promoteUser(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/moderation/$streamId/promote'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  Future<void> demoteUser(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/moderation/$streamId/demote'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }
}

final moderationServiceProvider = Provider<ModerationService>((ref) =>
    ModerationService(ref.watch(apiClientProvider)));
