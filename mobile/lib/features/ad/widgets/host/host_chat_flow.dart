import 'package:flutter/material.dart';

import '../../models/live_bid.dart';

/// Ephemeral chat messages overlaid on the camera (portrait and landscape).
class HostChatFlow extends StatelessWidget {
  final List<EphemeralMessage> messages;
  final double height;
  final String? currentUserId;
  final void Function(String identity, String name) onModerate;
  final void Function(String userId) onInvite;

  const HostChatFlow({
    super.key,
    required this.messages,
    required this.height,
    required this.currentUserId,
    required this.onModerate,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0.0, 0.4, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SizedBox(
        height: height,
        child: ListView.builder(
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[messages.length - 1 - index];
            final isOther = msg.senderId != null &&
                msg.senderId != currentUserId &&
                msg.senderName != 'Sistem';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: isOther
                          ? () => onModerate(msg.senderId!, msg.senderName)
                          : null,
                      child: Text('${msg.senderName}:',
                          style: TextStyle(
                              color: isOther
                                  ? Colors.blueAccent
                                  : Colors.white70,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              decoration: isOther
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationStyle:
                                  TextDecorationStyle.dotted)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(msg.text,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500))),
                    if (msg.senderId != null &&
                        msg.senderId != currentUserId)
                      GestureDetector(
                        onTap: () => onInvite(msg.senderId!),
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.mic,
                              color: Colors.blueAccent, size: 12),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
