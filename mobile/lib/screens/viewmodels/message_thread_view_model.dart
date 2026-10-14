import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/direct_message.dart';
import '../../repositories/message_repository.dart';
import '../../services/storage_service.dart';

class MessageThreadState {
  final List<DirectMessage> messages;
  final bool loading;
  final bool hasMore;
  final bool loadingMore;
  final bool hasError;

  const MessageThreadState({
    this.messages = const [],
    this.loading = true,
    this.hasMore = true,
    this.loadingMore = false,
    this.hasError = false,
  });

  MessageThreadState copyWith({
    List<DirectMessage>? messages,
    bool? loading,
    bool? hasMore,
    bool? loadingMore,
    bool? hasError,
  }) => MessageThreadState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    hasError: hasError ?? this.hasError,
  );
}

class MessageThreadViewModel
    extends AutoDisposeFamilyAsyncNotifier<MessageThreadState, int> {
  StreamSubscription<List<DirectMessage>>? _sub;

  int get _myId => StorageService.currentUserIdSync ?? 0;

  @override
  MessageThreadState build(int otherUserId) {
    final cached = ref.read(messageRepositoryProvider).getCachedThread(otherUserId, _myId);

    ref.onDispose(() => _sub?.cancel());
    Future.microtask(() => _startStream(otherUserId));

    return MessageThreadState(
      messages: cached ?? [],
      loading: cached == null,
    );
  }

  void _startStream(int otherUserId) {
    _sub?.cancel();
    _sub = ref
        .read(messageRepositoryProvider)
        .getThread(otherUserId, _myId)
        .listen(
          (msgs) {
            final current = state.valueOrNull;
            state = AsyncValue.data(
              (current ?? const MessageThreadState()).copyWith(
                messages: msgs,
                loading: false,
                hasError: false,
              ),
            );
          },
          onError: (_) {
            final current = state.valueOrNull;
            state = AsyncValue.data(
              (current ?? const MessageThreadState()).copyWith(
                hasError: true,
                loading: false,
              ),
            );
          },
        );
  }

  /// Yukarı scroll — önceki sayfa, sadece RAM'de tutulur.
  Future<void> loadPreviousPage() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final oldest = current.messages.first.id;
      final page = await ref
          .read(messageRepositoryProvider)
          .getPage(arg, oldest);
      state = AsyncValue.data(current.copyWith(
        messages: [...page, ...current.messages],
        hasMore: page.length == 50,
        loadingMore: false,
      ));
    } catch (_) {
      state = AsyncValue.data(current.copyWith(loadingMore: false));
    }
  }

  /// WS events — DirectChatScreen buraya iletir.
  Future<void> handleWsEvent(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final repo = ref.read(messageRepositoryProvider);
    final current = state.valueOrNull;
    if (current == null) return;

    switch (type) {
      case 'message':
        final msg = DirectMessage.fromJson(data);
        state = AsyncValue.data(current.copyWith(
          messages: [...current.messages, msg],
        ));
        await repo.appendToCache(arg, data);

      case 'message_deleted':
        final id = data['id'] as int?;
        if (id == null) return;
        state = AsyncValue.data(current.copyWith(
          messages: current.messages.where((m) => m.id != id).toList(),
        ));
        await repo.removeFromCache(arg, id);

      case 'messages_read':
        state = AsyncValue.data(current.copyWith(
          messages: current.messages
              .map((m) =>
                  m.senderId == _myId ? m.copyWith(isRead: true) : m)
              .toList(),
        ));
        await repo.markReadInCache(arg, _myId);
    }
  }

  /// Upload API response — WS olmadan doğrudan onaylanan mesajı ekle.
  void addConfirmedMessage(DirectMessage msg) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.messages.any((m) => m.id == msg.id)) return;
    state = AsyncValue.data(current.copyWith(
      messages: [...current.messages, msg],
    ));
  }

  /// Mesaj sil — Repository üzerinden, cache günceller.
  Future<bool> deleteMessage(int messageId, {String scope = 'everyone'}) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncValue.data(current.copyWith(
      messages: current.messages.where((m) => m.id != messageId).toList(),
    ));
    final ok = await ref
        .read(messageRepositoryProvider)
        .deleteMessage(messageId, arg, scope: scope);
    if (!ok) {
      state = AsyncValue.data(current);
    }
    return ok;
  }

  /// SWR yenileme — uygulama ön plana gelince veya WS yeniden bağlanınca.
  void refresh() => _startStream(arg);
}

final messageThreadProvider = AsyncNotifierProvider.autoDispose
    .family<MessageThreadViewModel, MessageThreadState, int>(
  MessageThreadViewModel.new,
);
