import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ad.dart';
import '../../controllers/live_arena_viewer_controller.dart';
import '../floating_reactions.dart';

class ViewerSidebar extends ConsumerWidget {
  final AdModel ad;
  final bool isPortrait;
  final VoidCallback onShowAdDetails;

  const ViewerSidebar({
    super.key,
    required this.ad,
    required this.isPortrait,
    required this.onShowAdDetails,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewerState = ref.watch(viewerControllerProvider(ad));
    final controller = ref.read(viewerControllerProvider(ad).notifier);

    return Positioned(
      right: 16,
      top: 0,
      bottom: 120,
      child: Center(
        child: SingleChildScrollView(
          clipBehavior: Clip.none,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ViewerCircularButton(
                  icon: Icons.info_outline, onPressed: onShowAdDetails),
              const SizedBox(height: 16),
              ViewerCircularButton(
                icon: viewerState.isMuted
                    ? Icons.volume_off
                    : Icons.volume_up,
                onPressed: () =>
                    controller.setIsMuted(!viewerState.isMuted),
              ),
              const SizedBox(height: 16),
              ViewerCircularButton(
                icon: Icons.mic_none,
                onPressed: () => controller.requestStage(context),
              ),
              const SizedBox(height: 16),
              ViewerCircularButton(
                icon: Icons.cameraswitch_outlined,
                onPressed: () {}, // Ghosted
              ),
              const SizedBox(height: 24),
              ReactionButtons(
                  onReact: controller.sendReaction, isVertical: true),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ViewerCircularButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? badge;

  const ViewerCircularButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.2)),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: Text(badge!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
