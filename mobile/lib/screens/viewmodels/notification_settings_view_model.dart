import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/notification_prefs_repository.dart';

class NotificationSettingsState {
  final Map<String, bool> prefs;
  final int bidThreshold;
  final bool quietEnabled;
  final TimeOfDay quietFrom;
  final TimeOfDay quietTo;
  final bool receiveBlastNotifications;
  final bool analyticsOptOut;

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
    this.analyticsOptOut = false,
  });

  NotificationSettingsState copyWith({
    Map<String, bool>? prefs,
    int? bidThreshold,
    bool? quietEnabled,
    TimeOfDay? quietFrom,
    TimeOfDay? quietTo,
    bool? receiveBlastNotifications,
    bool? analyticsOptOut,
  }) {
    return NotificationSettingsState(
      prefs: prefs ?? this.prefs,
      bidThreshold: bidThreshold ?? this.bidThreshold,
      quietEnabled: quietEnabled ?? this.quietEnabled,
      quietFrom: quietFrom ?? this.quietFrom,
      quietTo: quietTo ?? this.quietTo,
      receiveBlastNotifications: receiveBlastNotifications ?? this.receiveBlastNotifications,
      analyticsOptOut: analyticsOptOut ?? this.analyticsOptOut,
    );
  }
}

class NotificationSettingsViewModel
    extends AutoDisposeAsyncNotifier<NotificationSettingsState> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  static TimeOfDay _parseTime(String hhmm) {
    try {
      final parts = hhmm.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static NotificationSettingsState _fromMap(Map<String, dynamic> data) {
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
      analyticsOptOut: (data['analytics_opt_out'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> _toPayload(NotificationSettingsState s) => {
        ...s.prefs,
        'bid_threshold_tl': s.bidThreshold,
        'quiet_hours_enabled': s.quietEnabled,
        'quiet_from': _formatTime(s.quietFrom),
        'quiet_to': _formatTime(s.quietTo),
        'receive_blast_notifications': s.receiveBlastNotifications,
        'analytics_opt_out': s.analyticsOptOut,
      };

  @override
  FutureOr<NotificationSettingsState> build() {
    final repo = ref.read(notificationPrefsRepositoryProvider);
    final cachedRaw = repo.getCached();
    final initial = cachedRaw != null
        ? _fromMap(Map<String, dynamic>.from(cachedRaw as Map))
        : const NotificationSettingsState();

    _sub?.cancel();
    _sub = repo.getPrefs().listen(
      (data) {
        if (state.hasValue) {
          state = AsyncValue.data(_fromMap(data));
        }
      },
      onError: (_) {},
    );
    ref.onDispose(() => _sub?.cancel());

    return initial;
  }

  Future<void> _patch(NotificationSettingsState newState) async {
    try {
      await ref
          .read(notificationPrefsRepositoryProvider)
          .patchPrefs(_toPayload(newState));
    } catch (_) {}
  }

  Future<void> togglePref(String key, bool value) async {
    final current = state.value;
    if (current == null) return;
    final newPrefs = Map<String, bool>.from(current.prefs)..[key] = value;
    final newState = current.copyWith(prefs: newPrefs);
    state = AsyncValue.data(newState);
    try {
      await ref
          .read(notificationPrefsRepositoryProvider)
          .patchPrefs(_toPayload(newState));
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
    final newState =
        isFrom ? current.copyWith(quietFrom: time) : current.copyWith(quietTo: time);
    state = AsyncValue.data(newState);
    await _patch(newState);
  }

  Future<void> toggleAnalyticsOptOut(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newState = current.copyWith(analyticsOptOut: value);
    state = AsyncValue.data(newState);
    await _patch(newState);
  }
}

final notificationSettingsProvider =
    AsyncNotifierProvider.autoDispose<NotificationSettingsViewModel, NotificationSettingsState>(
  () => NotificationSettingsViewModel(),
);
