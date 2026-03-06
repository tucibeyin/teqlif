import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ad.dart';
import '../../controllers/live_arena_host_controller.dart';

/// Bottom row: Reset, Start/Stop, Countdown timer, Chat input.
class HostAuctionInput extends ConsumerWidget {
  final AdModel ad;
  final TextEditingController chatCtrl;
  final FocusNode chatFocus;
  final Animation<double> pulseAnimation;
  final int countdown;
  final VoidCallback onStartCountdown;

  const HostAuctionInput({
    super.key,
    required this.ad,
    required this.chatCtrl,
    required this.chatFocus,
    required this.pulseAnimation,
    required this.countdown,
    required this.onStartCountdown,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostControllerProvider(ad.id));
    final controller = ref.read(hostControllerProvider(ad.id).notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Reset button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => controller.resetAuction(context),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child:
                    const Icon(Icons.refresh, color: Colors.white, size: 28),
              ),
            ),
          ),
          // Start / Stop toggle
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => controller.toggleAuction(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: state.isAuctionActive
                      ? Colors.redAccent
                      : Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                  boxShadow: state.isAuctionActive
                      ? [
                          BoxShadow(
                              color: Colors.redAccent.withOpacity(0.4),
                              blurRadius: 15)
                        ]
                      : null,
                ),
                child: Icon(
                    state.isAuctionActive ? Icons.stop : Icons.play_arrow,
                    color: Colors.white,
                    size: 30),
              ),
            ),
          ),
          // Countdown button (only when auction active)
          if (state.isAuctionActive)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: onStartCountdown,
                child: AnimatedBuilder(
                    animation: pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: countdown > 0 && countdown <= 10
                            ? 1.0 + (pulseAnimation.value * 0.15)
                            : 1.0,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: countdown > 0 ? Colors.red : Colors.orange,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: (countdown > 0
                                          ? Colors.red
                                          : Colors.orange)
                                      .withOpacity(0.5),
                                  blurRadius: 15)
                            ],
                          ),
                          child: Center(
                            child: countdown > 0
                                ? Text('$countdown',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 24))
                                : const Icon(Icons.timer,
                                    color: Colors.white, size: 28),
                          ),
                        ),
                      );
                    }),
              ),
            ),
          // Chat input
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: chatCtrl,
                          focusNode: chatFocus,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'Sohbete dahil ol...',
                            hintStyle: TextStyle(
                                color: Colors.black54, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          onSubmitted: (_) => _send(controller),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send,
                            color: Color(0xFF00B4CC)),
                        onPressed: () => _send(controller),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send(HostController controller) {
    final text = chatCtrl.text.trim();
    if (text.isEmpty) return;
    controller.sendChatMessage(text);
    chatCtrl.clear();
    chatFocus.unfocus();
  }
}
