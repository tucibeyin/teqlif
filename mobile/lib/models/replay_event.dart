import '../models/recording.dart';
import '../services/localization_service.dart';

enum ReplayEventType { bid, gift, purchase, chat }

class ReplayEvent {
  final double offsetSecs;
  final ReplayEventType type;
  final String username;
  final String? avatarUrl;
  final String label;

  const ReplayEvent({
    required this.offsetSecs,
    required this.type,
    required this.username,
    this.avatarUrl,
    required this.label,
  });

  factory ReplayEvent.bid(
    RecordingBid bid,
    String itemName,
    TranslationPack loc,
  ) =>
      ReplayEvent(
        offsetSecs: bid.offsetSecs!,
        type: ReplayEventType.bid,
        username: bid.username,
        avatarUrl: bid.avatarUrl,
        label: loc
            .t('replayBidRow')
            .replaceAll('{username}', bid.username)
            .replaceAll('{amount}', bid.amount.toStringAsFixed(2)),
      );

  factory ReplayEvent.gift(
    RecordingGiftEvent gift,
    TranslationPack loc,
  ) =>
      ReplayEvent(
        offsetSecs: gift.offsetSecs!,
        type: ReplayEventType.gift,
        username: gift.username,
        avatarUrl: gift.avatarUrl,
        label: loc
            .t('replayGiftRow')
            .replaceAll('{username}', gift.username)
            .replaceAll('{giftName}', gift.giftName),
      );

  factory ReplayEvent.purchase(
    RecordingOrder order,
    String itemTitle,
    TranslationPack loc,
  ) =>
      ReplayEvent(
        offsetSecs: order.offsetSecs!,
        type: ReplayEventType.purchase,
        username: order.username,
        avatarUrl: order.avatarUrl,
        label: loc
            .t('replayPurchaseRow')
            .replaceAll('{username}', order.username)
            .replaceAll('{itemTitle}', itemTitle)
            .replaceAll('{quantity}', '${order.quantity}'),
      );

  factory ReplayEvent.chat(
    RecordingChatMessage message,
  ) =>
      ReplayEvent(
        offsetSecs: message.offsetSecs!,
        type: ReplayEventType.chat,
        username: message.username,
        avatarUrl: message.avatarUrl,
        label: message.content,
      );
}
