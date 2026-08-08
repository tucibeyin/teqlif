import 'package:flutter/foundation.dart';

sealed class CommerceEvent {
  const CommerceEvent();
  String get actor;
  DateTime get createdAt;
}

@immutable
class AuctionBidEvent extends CommerceEvent {
  @override
  final String actor;
  final double amount;
  @override
  final DateTime createdAt;

  const AuctionBidEvent({
    required this.actor,
    required this.amount,
    required this.createdAt,
  });
}

@immutable
class DsPurchaseEvent extends CommerceEvent {
  @override
  final String actor;
  final double unitPrice;
  final int quantity;
  @override
  final DateTime createdAt;

  const DsPurchaseEvent({
    required this.actor,
    required this.unitPrice,
    required this.quantity,
    required this.createdAt,
  });
}

@immutable
class CommerceEventGroup {
  final String? title;
  final String groupType; // "auction" | "ds"
  final List<CommerceEvent> events;

  const CommerceEventGroup({
    this.title,
    required this.groupType,
    required this.events,
  });

  CommerceEventGroup copyWith({List<CommerceEvent>? events}) {
    return CommerceEventGroup(
      title: title,
      groupType: groupType,
      events: events ?? this.events,
    );
  }
}
