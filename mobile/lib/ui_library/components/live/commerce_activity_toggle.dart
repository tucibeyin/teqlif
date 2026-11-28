import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/live/live_press_btn.dart';
import 'commerce_activity_overlay.dart';

class CommerceActivityToggle extends ConsumerStatefulWidget {
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
  ConsumerState<CommerceActivityToggle> createState() =>
      _CommerceActivityToggleState();
}

class _CommerceActivityToggleState extends ConsumerState<CommerceActivityToggle>
    with TickerProviderStateMixin {
  // 0.0 turns = kapalı (sol ok), 0.5 turns = açık (sağ ok, 180°)
  late final AnimationController _rotCtrl;
  late final Animation<double> _rotAnim;

  // Yeni işlem geldiğinde tetiklenir; panel açılınca durur
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _rotAnim = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _rotCtrl, curve: Curves.easeInOut),
    );
    if (widget.isOpen) _rotCtrl.value = 1.0;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // begin:1.0 → controller=0.0 (idle) = tam opaklık
    _pulseAnim = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(CommerceActivityToggle old) {
    super.didUpdateWidget(old);

    if (widget.isOpen != old.isOpen) {
      if (widget.isOpen) {
        _rotCtrl.forward();
        _pulseCtrl.stop();
        _pulseCtrl.reset();
      } else {
        _rotCtrl.reverse();
      }
    }

    if (!widget.isOpen && widget.count > old.count && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    const radius =
        BorderRadiusDirectional.horizontal(start: Radius.circular(12));
    final borderColor =
        Colors.white.withValues(alpha: widget.isOpen ? 0.10 : 0.15);

    final chevron = RotationTransition(
      turns: _rotAnim,
      child: const Icon(
        Icons.chevron_left_rounded,
        color: Color(0xFF64748B),
        size: 18,
      ),
    );

    return LivePressBtn(
      onTap: widget.onToggle,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            clipBehavior: Clip.hardEdge,
            width: widget.isOpen ? 32 : 38,
            height: widget.isOpen ? kCommerceActivityH / 2 : 160,
            padding: widget.isOpen
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black
                  .withValues(alpha: widget.isOpen ? 0.42 : 0.52),
              borderRadius: radius,
              border: Border(
                left: BorderSide(color: borderColor),
                top: BorderSide(color: borderColor),
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: widget.isOpen
                ? Center(child: chevron)
                : _closedChild(loc, chevron),
          ),
        ),
      ),
    );
  }

  Widget _closedChild(TranslationPack loc, Widget chevron) {
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
            '${widget.count}',
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
              color: Color(0xFFCBD5E1),
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: _pulseAnim,
          child: chevron,
        ),
      ],
    );
  }
}
