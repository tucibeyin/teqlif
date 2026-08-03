import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';

class NotificationSettingsState {
  final Map<String, bool> prefs;
  final int bidThreshold;
  final bool quietEnabled;
  final TimeOfDay quietFrom;
  final TimeOfDay quietTo;
  final bool receiveBlastNotifications;

  const NotificationSettingsState({
    this.prefs = const {
      'messages': true,
      'follows': true,
      'auction_won': true,
      'stream_started': true,
      'new_listing': true,
      'new_bid': true,
      'outbid': true,
      'ratings': true,
    },
    this.bidThreshold = 0,
    this.quietEnabled = false,
    this.quietFrom = const TimeOfDay(hour: 22, minute: 0),
    this.quietTo = const TimeOfDay(hour: 8, minute: 0),
    this.receiveBlastNotifications = true,
  });

  NotificationSettingsState copyWith({
    Map<String, bool>? prefs,
    int? bidThreshold,
    bool? quietEnabled,
    TimeOfDay? quietFrom,
    TimeOfDay? quietTo,
    bool? receiveBlastNotifications,
  }) {
    return NotificationSettingsState(
      prefs: prefs ?? this.prefs,
      bidThreshold: bidThreshold ?? this.bidThreshold,
      quietEnabled: quietEnabled ?? this.quietEnabled,
      quietFrom: quietFrom ?? this.quietFrom,
      quietTo: quietTo ?? this.quietTo,
      receiveBlastNotifications: receiveBlastNotifications ?? this.receiveBlastNotifications,
    );
  }
}

class NotificationSettingsViewModel extends AutoDisposeAsyncNotifier<NotificationSettingsState> {
  TimeOfDay _parseTime(String hhmm) {
    try {
      final parts = hhmm.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  FutureOr<NotificationSettingsState> build() async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Unauthenticated');
    }
    
    final resp = await http.get(
      Uri.parse('$kBaseUrl/auth/notification-prefs'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final initialPrefs = const NotificationSettingsState().prefs;
      final newPrefs = Map<String, bool>.from(initialPrefs);
      
      for (final k in newPrefs.keys) {
        newPrefs[k] = data[k] as bool? ?? true;
      }
      
      return NotificationSettingsState(
        prefs: newPrefs,
        bidThreshold: (data['bid_threshold_tl'] as int?) ?? 0,
        quietEnabled: (data['quiet_hours_enabled'] as bool?) ?? false,
        quietFrom: _parseTime(data['quiet_from'] as String? ?? '22:00'),
        quietTo: _parseTime(data['quiet_to'] as String? ?? '08:00'),
        receiveBlastNotifications: (data['receive_blast_notifications'] as bool?) ?? true,
      );
    } else {
      throw Exception('Failed to load preferences');
    }
  }

  Map<String, dynamic> _buildPayload(NotificationSettingsState s) => {
    ...s.prefs,
    'bid_threshold_tl': s.bidThreshold,
    'quiet_hours_enabled': s.quietEnabled,
    'quiet_from': _formatTime(s.quietFrom),
    'quiet_to': _formatTime(s.quietTo),
    'receive_blast_notifications': s.receiveBlastNotifications,
  };

  Future<void> _patch(NotificationSettingsState newState) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$kBaseUrl/auth/notification-prefs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(_buildPayload(newState)),
      );
    } catch (_) {}
  }

  Future<void> togglePref(String key, bool value) async {
    final current = state.value;
    if (current == null) return;
    
    final newPrefs = Map<String, bool>.from(current.prefs);
    newPrefs[key] = value;
    
    final newState = current.copyWith(prefs: newPrefs);
    state = AsyncValue.data(newState);
    
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/auth/notification-prefs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(_buildPayload(newState)),
      );
      if (resp.statusCode >= 400) {
        state = AsyncValue.data(current);
      }
    } catch (_) {
      state = AsyncValue.data(current);
    }
  }

  Future<void> setBidThreshold(int value) async {
    final current = state.value;
    if (current == null) return;
    final newState = current.copyWith(bidThreshold: value);
    state = AsyncValue.data(newState);
    await _patch(newState);
  }

  Future<void> setQuietEnabled(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newState = current.copyWith(quietEnabled: value);
    state = AsyncValue.data(newState);
    await _patch(newState);
  }

  Future<void> setBlastNotifications(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newState = current.copyWith(receiveBlastNotifications: value);
    state = AsyncValue.data(newState);
    await _patch(newState);
  }

  Future<void> setQuietTime({required bool isFrom, required TimeOfDay time}) async {
    final current = state.value;
    if (current == null) return;
    final newState = isFrom 
        ? current.copyWith(quietFrom: time)
        : current.copyWith(quietTo: time);
    state = AsyncValue.data(newState);
    await _patch(newState);
  }
}

final notificationSettingsProvider = AsyncNotifierProvider.autoDispose<NotificationSettingsViewModel, NotificationSettingsState>(
  () => NotificationSettingsViewModel(),
);
