import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

enum TeqToastType { error, success, warning, info }

/// Overlay tabanlı tek satırlık bildirim widget'ı.
///
/// ScaffoldMessenger'a bağımlı değildir — canlı yayın ekranları dahil
/// her context'te çalışır. Aynı anda yalnızca bir toast görünür;
/// yeni bir çağrı mevcut toast'u hemen kaldırır.
class TeqToast {
  TeqToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    TeqToastType type = TeqToastType.error,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _current?.remove();
    _current = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TeqToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDone: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }

  static void error(BuildContext context, String message, {Duration? duration}) =>
      show(context, message: message, type: TeqToastType.error, duration: duration ?? const Duration(seconds: 3));

  static void success(BuildContext context, String message, {Duration? duration}) =>
      show(context, message: message, type: TeqToastType.success, duration: duration ?? const Duration(seconds: 3));

  static void warning(BuildContext context, String message, {Duration? duration}) =>
      show(context, message: message, type: TeqToastType.warning, duration: duration ?? const Duration(seconds: 4));

  static void info(BuildContext context, String message, {Duration? duration}) =>
      show(context, message: message, type: TeqToastType.info, duration: duration ?? const Duration(seconds: 4));
}

class _TeqToastWidget extends StatefulWidget {
  final String message;
  final TeqToastType type;
  final Duration duration;
  final VoidCallback onDone;

  const _TeqToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_TeqToastWidget> createState() => _TeqToastWidgetState();
}

class _TeqToastWidgetState extends State<_TeqToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();

    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  (Color bg, IconData icon) get _style => switch (widget.type) {
        TeqToastType.error   => (TeqColors.error,   Icons.error_outline),
        TeqToastType.success => (TeqColors.success,  Icons.check_circle_outline),
        TeqToastType.warning => (TeqColors.warning,  Icons.warning_amber_outlined),
        TeqToastType.info    => (TeqColors.info,     Icons.info_outline),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, icon) = _style;
    final bottom = MediaQuery.of(context).padding.bottom +
        MediaQuery.of(context).viewInsets.bottom +
        TeqSpacing.m;

    return Positioned(
      left: TeqSpacing.m,
      right: TeqSpacing.m,
      bottom: bottom,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: TeqSpacing.m,
                vertical: TeqSpacing.s,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(TeqSpacing.radiusL),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: TeqSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TeqTypography.bodyMedium.copyWith(
                        color: Colors.white,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
