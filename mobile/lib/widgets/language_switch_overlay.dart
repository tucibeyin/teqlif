import 'dart:ui';
import 'package:flutter/material.dart';

class LanguageSwitchOverlay extends StatelessWidget {
  final Widget child;
  final bool isVisible;

  const LanguageSwitchOverlay({
    super.key,
    required this.child,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isVisible)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.25),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
