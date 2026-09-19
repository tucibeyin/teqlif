import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/app_exception.dart';
import '../models/stream.dart';
import 'api_service.dart';
import 'storage_service.dart';

class StreamService {
  final ApiClient _api;
  StreamService(this._api);
  late final _apiService = ApiService(_api);

  /// Kullanıcı aktif olarak yayın yapıyor mu?
  /// HostStreamScreen initState/dispose tarafından set edilir.
  /// _handleNotifNavigation bu flag'i kontrol ederek yayıncıyı
  /// başka yayınlara yönlendirmez.
  static bool isHosting = false;

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: true);
  }

  Future<List<StreamOut>> getActiveStreams() async {
    final headers = await _headers();
    final resp = await http.get(Uri.parse('${_api.config.baseUrl}/streams/active'), headers: headers);
    debugPrint('[StreamService] getActiveStreams → HTTP ${resp.statusCode}, body: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
    if (resp.statusCode >= 400) _throwHttpError(resp.statusCode, resp.body);
    final list = _tryDecodeList(resp.body);
    debugPrint('[StreamService] getActiveStreams → parse edilen öğe sayısı: ${list.length}');
    final result = <StreamOut>[];
    for (final e in list) {
      try {
        result.add(StreamOut.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('[StreamService] StreamOut.fromJson hatası: $err | veri: $e');
      }
    }
    return result;
  }

  /// SWR Stream versiyonu: önce Hive cache (anlık), sonra API (taze).
  /// [bypassCache]: pull-to-refresh veya LiveList her açılışında true.
  /// TTL: 1 dakika (yayınlar gerçek zamanlı değişir).
  Stream<List<StreamOut>> getActiveStreamsStream({bool bypassCache = false}) =>
      _apiService.get<List<StreamOut>>(
        url: '${_api.config.baseUrl}/streams/active',
        cacheKey: 'active_streams',
        cacheTtl: const Duration(minutes: 1),
        bypassCache: bypassCache,
        fromJson: (raw) {
          final list = raw as List;
          final result = <StreamOut>[];
          for (final e in list) {
            try {
              result.add(StreamOut.fromJson(e as Map<String, dynamic>));
            } catch (err) {
              debugPrint('[StreamService] SWR parse hatası: $err | veri: $e');
            }
          }
          return result;
        },
      );

  Future<List<StreamOut>> getRecommendedStreams() async {
    final headers = await _headers();
    final token = await StorageService.getToken();
    if (token == null) return [];
    final resp = await http.get(Uri.parse('${_api.config.baseUrl}/streams/recommended'), headers: headers);
    if (resp.statusCode >= 400) return [];
    final list = _tryDecodeList(resp.body);
    final result = <StreamOut>[];
    for (final e in list) {
      try {
        result.add(StreamOut.fromJson(e as Map<String, dynamic>));
      } catch (_) {}
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getSuggestedStreamers() async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('${_api.config.baseUrl}/streams/suggested-streamers'),
      headers: headers,
    );
    if (resp.statusCode >= 400) return [];
    return _tryDecodeList(resp.body).cast<Map<String, dynamic>>();
  }

  Future<List<StreamOut>> getFollowedLiveStreams() async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('${_api.config.baseUrl}/streams/following/live'),
      headers: headers,
    );
    if (resp.statusCode >= 400) _throwHttpError(resp.statusCode, resp.body);
    final list = _tryDecodeList(resp.body);
    return list
        .map((e) => StreamOut.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StreamTokenOut> startStream(
    String title,
    String category,
    String subcategory, {
    String? captchaToken,
  }) async {
    final headers = await _headers();
    if (captchaToken != null && captchaToken.isNotEmpty) {
      headers['X-Captcha-Token'] = captchaToken;
    }
    final body = await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/streams/start'),
        headers: headers,
        body: jsonEncode({'title': title, 'category': category, 'subcategory': subcategory}),
      ),
    );
    return StreamTokenOut.fromJson(body);
  }

  Future<void> endStream(int streamId) async {
    await _api.call(
      () async => http.post(Uri.parse('${_api.config.baseUrl}/streams/$streamId/end'), headers: await _headers()),
    );
  }

  /// LiveKit bağlantısı kurulduktan sonra çağrılır — yayını canlıya alır ve bildirimleri tetikler.
  Future<void> confirmLive(int streamId) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/confirm-live'),
        headers: await _headers(),
      ),
    );
  }

  /// LiveKit bağlantısı kurulamazsa çağrılır — pending kaydı siler.
  Future<void> cancelStream(int streamId) async {
    try {
      await http.delete(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/cancel'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<bool> isStreamActive(int streamId) async {
    try {
      final body = await _api.call(
        () async => http.get(Uri.parse('${_api.config.baseUrl}/streams/$streamId/check'), headers: await _headers()),
      );
      return body['active'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<JoinTokenOut> joinStream(int streamId) async {
    final body = await _api.call(
      () async => http.post(Uri.parse('${_api.config.baseUrl}/streams/$streamId/join'), headers: await _headers()),
    );
    return JoinTokenOut.fromJson(body);
  }

  /// Canlı yayına kalp gönder (add-only, backend throttle olmadan — istemci throttle'ı kullanır).
  Future<void> likeStream(int streamId) async {
    await http.post(
      Uri.parse('${_api.config.baseUrl}/streams/$streamId/like'),
      headers: await _headers(),
    );
  }

  Future<void> leaveStream(int streamId) async {
    await http.delete(
      Uri.parse('${_api.config.baseUrl}/streams/$streamId/leave'),
      headers: await _headers(),
    );
  }

  Future<void> pipEnter(int streamId) async {
    try {
      await http.post(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/pip-enter'),
        headers: await _headers(),
      );
    } catch (_) {}
  }

  Future<void> pipExit(int streamId) async {
    try {
      await http.delete(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/pip-exit'),
        headers: await _headers(),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getViewers(int streamId) async {
    final headers = await _headers();
    final resp = await http.get(Uri.parse('${_api.config.baseUrl}/streams/$streamId/viewers'), headers: headers);
    if (resp.statusCode >= 400) {
      throw AppException('İzleyiciler alınamadı', statusCode: resp.statusCode);
    }
    final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(
      (body['viewers'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<String> uploadThumbnail(int streamId, Uint8List bytes, String filename) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest(
      'PATCH',
      Uri.parse('${_api.config.baseUrl}/streams/$streamId/thumbnail'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final bodyStr = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      _throwHttpError(streamed.statusCode, bodyStr, fallback: 'Thumbnail yüklenemedi');
    }
    return (_tryDecode(bodyStr)['thumbnail_url'] as String);
  }

  /// Bir izleyiciyi sahneye davet et (host → POST /cohost/invite).
  Future<void> inviteCoHost(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/cohost/invite'),
        headers: await _headers(),
        body: jsonEncode({'target_username': username}),
      ),
    );
  }

  /// Sahne davetini kabul et — yeni can_publish=true token döner (viewer → POST /cohost/accept).
  Future<StreamTokenOut> acceptCoHostInvite(int streamId) async {
    final body = await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/cohost/accept'),
        headers: await _headers(),
      ),
    );
    return StreamTokenOut.fromJson(body);
  }

  /// Sahnedeki konuğu kaldır (host → POST /cohost/remove).
  Future<void> removeCoHost(int streamId, String username) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/cohost/remove'),
        headers: await _headers(),
        body: jsonEncode({'target_username': username}),
      ),
    );
  }

  /// Reconnect için taze token al — stream sona erdiyse 410 → STREAM_ENDED fırlatır.
  /// Host: can_publish=True token. Viewer: can_publish=False token.
  Future<StreamTokenOut> refreshStreamToken(int streamId) async {
    final body = await _api.call(
      () async => http.get(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/token'),
        headers: await _headers(),
      ),
    );
    return StreamTokenOut.fromJson(body);
  }

  /// Gönüllü sahneden ayrıl — cohost_removed WS sinyali yayınlanır (viewer → POST /cohost/leave).
  Future<void> leaveCoHost(int streamId) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/cohost/leave'),
        headers: await _headers(),
      ),
    );
  }

  /// HTTP hata yanıtını parse eder ve [AppException] fırlatır.
  static Never _throwHttpError(int statusCode, String body, {String fallback = 'Bir hata oluştu'}) {
    final decoded = _tryDecode(body);
    final errMap = decoded['error'];
    throw AppException(
      errMap is Map ? (errMap['message'] ?? fallback) : (decoded['detail'] ?? fallback),
      code: errMap is Map ? (errMap['code'] ?? 'ERR_$statusCode') : 'HTTP_$statusCode',
      statusCode: statusCode,
    );
  }

  static Map<String, dynamic> _tryDecode(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  static List _tryDecodeList(String body) {
    try { return jsonDecode(body) as List; } catch (_) { return []; }
  }

  Future<Map<String, dynamic>> fetchAudienceInsights(int streamId) async {
    final token = await StorageService.getToken();
    final resp = await http.get(
      Uri.parse('${_api.config.baseUrl}/streams/$streamId/audience-insights'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    _throwHttpError(resp.statusCode, resp.body, fallback: 'Bütçe analizi alınamadı');
  }

  /// Kullanıcıya özel SwipeLive konfigürasyonu: sıralanmış yayınlar + listings_per_group.
  /// Hata olursa null döner — çağıran varsayılan davranışa düşer.
  Future<SwipeLiveConfig?> getSwipeLiveConfig() async {
    try {
      final headers = await _headers();
      final resp = await http
          .get(Uri.parse('${_api.config.baseUrl}/streams/swipe-live-config'), headers: headers)
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        return SwipeLiveConfig.fromJson(
            await compute(jsonDecode, resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchCommerceActivity(int streamId) async {
    try {
      final headers = await _headers();
      final resp = await http
          .get(Uri.parse('${_api.config.baseUrl}/streams/$streamId/commerce-activity'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// SwipeLive davranış eventlerini batch olarak gönderir. Fire-and-forget.
  Future<void> sendSwipeLiveEvents(
      List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    try {
      final headers = await _headers();
      await http
          .post(
            Uri.parse('${_api.config.baseUrl}/analytics/swipe-live-events'),
            headers: headers,
            body: jsonEncode({'events': events}),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }
}

final streamServiceProvider = Provider<StreamService>((ref) =>
    StreamService(ref.watch(apiClientProvider)));
