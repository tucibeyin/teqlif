import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../core/result.dart';
import '../../models/recording.dart';
import '../../models/replay_event.dart';
import '../../services/localization_service.dart';
import '../../services/recordings/recording_repository.dart';
import '../../utils/error_helper.dart';

class RecordingDetailState {
  final RecordingUrlData? urlData;
  final RecordingDetail? summary;
  final bool summaryLoading;
  final bool summaryFailed;
  final String? urlError;
  final List<ReplayEvent> timeline;
  final bool replayEnabled;
  final List<RecordingParticipantActivity> participants;

  const RecordingDetailState({
    this.urlData,
    this.summary,
    this.summaryLoading = false,
    this.summaryFailed = false,
    this.urlError,
    this.timeline = const [],
    this.replayEnabled = false,
    this.participants = const [],
  });

  RecordingDetailState copyWith({
    RecordingUrlData? urlData,
    RecordingDetail? summary,
    bool? summaryLoading,
    bool? summaryFailed,
    String? urlError,
    bool clearUrlError = false,
    List<ReplayEvent>? timeline,
    bool? replayEnabled,
    List<RecordingParticipantActivity>? participants,
  }) {
    return RecordingDetailState(
      urlData:       urlData       ?? this.urlData,
      summary:       summary       ?? this.summary,
      summaryLoading: summaryLoading ?? this.summaryLoading,
      summaryFailed: summaryFailed ?? this.summaryFailed,
      urlError:      clearUrlError ? null : (urlError ?? this.urlError),
      timeline:      timeline      ?? this.timeline,
      replayEnabled: replayEnabled ?? this.replayEnabled,
      participants:  participants  ?? this.participants,
    );
  }
}

class RecordingDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<RecordingDetailState, int> {
  late int _streamId;

  @override
  FutureOr<RecordingDetailState> build(int streamId) async {
    _streamId = streamId;
    final initial = await _loadAll();
    // URL yüklendikten hemen sonra summary fetch'i başlat.
    // Future.microtask build() döndükten sonra çalışır — state hazır.
    Future.microtask(fetchSummary);
    return initial;
  }

  Future<RecordingDetailState> _loadAll() async {
    final urlResult = await ref
        .read(recordingRepositoryProvider)
        .getRecordingUrl(_streamId);

    RecordingUrlData? urlData;
    String? urlError;

    switch (urlResult) {
      case Ok(:final value):
        urlData = value;
      case Err(:final error):
        urlError = _errorMessage(error);
    }

    return RecordingDetailState(urlData: urlData, urlError: urlError);
  }

  /// 403 sonrası presigned URL'yi yeniden çeker (cache bypass).
  Future<void> recoverUrl() async {
    final current = state.valueOrNull ?? const RecordingDetailState();
    state = AsyncValue.data(current.copyWith(clearUrlError: true));

    final result = await ref
        .read(recordingRepositoryProvider)
        .getRecordingUrl(_streamId, bypassCache: true);

    switch (result) {
      case Ok(:final value):
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(urlData: value, clearUrlError: true),
        );
      case Err(:final error):
        final msg = _errorMessage(error);
        handleError(error, ref.read(localizationProvider));
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(urlError: msg),
        );
    }
  }

  /// Commerce özet verisi — talep üzerine yüklenir.
  Future<void> fetchSummary() async {
    final current = state.valueOrNull ?? const RecordingDetailState();
    if (current.summary != null || current.summaryLoading || current.summaryFailed) return;

    state = AsyncValue.data(current.copyWith(summaryLoading: true));

    final result = await ref
        .read(recordingRepositoryProvider)
        .getRecordingSummary(_streamId);

    switch (result) {
      case Ok(:final value):
        final loc = ref.read(localizationProvider);
        final timeline = _buildTimeline(value, loc);
        final replayEnabled = value.stream.recordingStartedAt != null &&
            timeline.isNotEmpty;
        final participants = _buildParticipants(value);
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState()).copyWith(
            summary: value,
            summaryLoading: false,
            summaryFailed: false,
            timeline: timeline,
            replayEnabled: replayEnabled,
            participants: participants,
          ),
        );
      case Err(:final error):
        handleError(error, ref.read(localizationProvider));
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(summaryLoading: false, summaryFailed: true),
        );
    }
  }

  /// Başarısız summary fetch'i yeniden dener.
  Future<void> retrySummary() async {
    final current = state.valueOrNull ?? const RecordingDetailState();
    if (current.summary != null) return;
    state = AsyncValue.data(current.copyWith(summaryFailed: false));
    await fetchSummary();
  }

  List<RecordingParticipantActivity> _buildParticipants(RecordingDetail detail) {
    final Map<int, ({String username, String? avatarUrl})> userMeta = {};
    final Map<int, List<ParticipantBidAction>> bids = {};
    final Map<int, List<ParticipantOrderAction>> orders = {};
    final Map<int, List<ParticipantGiftAction>> gifts = {};
    final Map<int, List<ParticipantChatAction>> chats = {};

    void ensureUser(int id, String username, String? avatarUrl) {
      userMeta.putIfAbsent(id, () => (username: username, avatarUrl: avatarUrl));
    }

    for (final a in detail.auctions) {
      for (final b in a.bids) {
        ensureUser(b.userId, b.username, b.avatarUrl);
        bids.putIfAbsent(b.userId, () => []).add(ParticipantBidAction(
          auctionName: a.itemName,
          amount: b.amount,
          offsetSecs: b.offsetSecs,
        ));
      }
    }

    for (final ds in detail.directSales) {
      for (final o in ds.orders) {
        ensureUser(o.userId, o.username, o.avatarUrl);
        orders.putIfAbsent(o.userId, () => []).add(ParticipantOrderAction(
          itemName: ds.title,
          quantity: o.quantity,
          unitPrice: o.unitPrice,
          offsetSecs: o.offsetSecs,
        ));
      }
    }

    for (final ge in detail.gifts.events) {
      ensureUser(ge.userId, ge.username, ge.avatarUrl);
      gifts.putIfAbsent(ge.userId, () => []).add(ParticipantGiftAction(
        giftName: ge.giftName,
        costTeqlik: ge.costTeqlik,
        offsetSecs: ge.offsetSecs,
      ));
    }

    for (final cm in detail.chatMessages) {
      if (cm.userId == null) continue;
      final uid = cm.userId!;
      ensureUser(uid, cm.username, cm.avatarUrl);
      chats.putIfAbsent(uid, () => []).add(ParticipantChatAction(
        content: cm.content,
        isHost: cm.isHost,
        isMod: cm.isMod,
        offsetSecs: cm.offsetSecs,
      ));
    }

    final allIds = {
      ...bids.keys,
      ...orders.keys,
      ...gifts.keys,
      ...chats.keys,
    };

    final result = allIds.map((uid) {
      final meta = userMeta[uid]!;
      return RecordingParticipantActivity(
        userId: uid,
        username: meta.username,
        avatarUrl: meta.avatarUrl,
        bids: bids[uid] ?? [],
        orders: orders[uid] ?? [],
        gifts: gifts[uid] ?? [],
        chats: chats[uid] ?? [],
      );
    }).toList();

    result.sort((a, b) => b.monetaryTotal.compareTo(a.monetaryTotal));
    return result;
  }

  List<ReplayEvent> _buildTimeline(RecordingDetail detail, TranslationPack loc) => [
        for (final a in detail.auctions)
          for (final b in a.bids)
            if (b.offsetSecs != null && b.offsetSecs! >= 0)
              ReplayEvent.bid(b, a.itemName, loc),
        for (final ds in detail.directSales)
          for (final o in ds.orders)
            if (o.offsetSecs != null && o.offsetSecs! >= 0)
              ReplayEvent.purchase(o, ds.title, loc),
        for (final ge in detail.gifts.events)
          if (ge.offsetSecs != null && ge.offsetSecs! >= 0)
            ReplayEvent.gift(ge, loc),
        for (final cm in detail.chatMessages)
          if (cm.offsetSecs != null && cm.offsetSecs! >= 0)
            ReplayEvent.chat(cm),
      ]..sort((a, b) => a.offsetSecs.compareTo(b.offsetSecs));

  String _errorMessage(Object error) {
    if (error is AppException) return error.code;
    return error.toString();
  }
}

final recordingDetailProvider = AsyncNotifierProvider.autoDispose
    .family<RecordingDetailNotifier, RecordingDetailState, int>(
  RecordingDetailNotifier.new,
);
