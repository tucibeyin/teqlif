class LiveBid {
  final String id;
  final double amount;
  final String userLabel;
  final DateTime timestamp;
  final bool isAccepted;
  final String? userId;

  LiveBid({
    required this.id,
    required this.amount,
    required this.userLabel,
    required this.timestamp,
    this.isAccepted = false,
    this.userId,
  });

  LiveBid copyWith({
    String? id,
    double? amount,
    String? userLabel,
    DateTime? timestamp,
    bool? isAccepted,
    String? userId,
  }) {
    return LiveBid(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      userLabel: userLabel ?? this.userLabel,
      timestamp: timestamp ?? this.timestamp,
      isAccepted: isAccepted ?? this.isAccepted,
      userId: userId ?? this.userId,
    );
  }
}

class EphemeralMessage {
  final String id;
  final String text;
  final String senderName;
  final DateTime timestamp;
  final String? senderId;

  EphemeralMessage({
    required this.id,
    required this.text,
    required this.senderName,
    required this.timestamp,
    this.senderId,
  });
}
