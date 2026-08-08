import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import 'commerce_activity_overlay.dart';

class CommerceActivityToggle extends ConsumerWidget {
  final bool isOpen;
  final int count;
  final VoidCallback onToggle;

  const CommerceActivityToggle({
    super.key,
    required this.isOpen,
    required this.count,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const radius =
        BorderRadiusDirectional.horizontal(start: Radius.circular(12));
    final borderColor =
        Colors.white.withValues(alpha: isOpen ? 0.10 : 0.15);

    return GestureDetector(
      onTap: onToggle,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            clipBehavior: Clip.hardEdge,
            width: isOpen ? 32 : 38,
            height:
                isOpen ? kCommerceActivityH / 2 : 160,
            padding: isOpen
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black
                  .withValues(alpha: isOpen ? 0.42 : 0.52),
              borderRadius: radius,
              border: Border(
                left: BorderSide(color: borderColor),
                top: BorderSide(color: borderColor),
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: isOpen
                ? _openChild()
                : _closedChild(ref.read(localizationProvider)),
          ),
        ),
      ),
    );
  }

  Widget _openChild() {
    return const Center(
      child: Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF64748B),
        size: 20,
      ),
    );
  }

  Widget _closedChild(TranslationPack loc) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFF334155),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        RotatedBox(
          quarterTurns: 3,
          child: Text(
            loc.t('lblCommerceActivity'),
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Icon(
          Icons.chevron_left_rounded,
          color: Color(0xFF64748B),
          size: 18,
        ),
      ],
    );
  }
}
