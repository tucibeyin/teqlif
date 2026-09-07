import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../foundation/teq_colors.dart';

/// Teqlif Design System — Voice Record Button
///
/// Long press to record, swipe left to cancel.
/// Handles all gesture + animation + haptic internally.
/// Parent drives [isRecording] state; business logic stays in parent callbacks.
class TeqVoiceButton extends StatefulWidget {
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final VoidCallback onRecordCancel;
  final bool isRecording;
  final double size;

  const TeqVoiceButton({
    super.key,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.onRecordCancel,
    required this.isRecording,
    this.size = 42,
  });

  @override
  State<TeqVoiceButton> createState() => _TeqVoiceButtonState();
}

class _TeqVoiceButtonState extends State<TeqVoiceButton>
    with TickerProviderStateMixin {
  // Scale: 0.0 = rest(1.0x), 0.55 = pressed(~1.2x), 1.0 = recording(1.35x)
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  // Pulse opacity while recording
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  bool _longPressActive = false;
  bool _isCancelling = false;

  static const double _cancelThresholdDx = -60.0;

  @override
  void initState() {
    super.initState();

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(TeqVoiceButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.isRecording) return;
    HapticFeedback.selectionClick();
    _scaleCtrl.animateTo(0.55, duration: const Duration(milliseconds: 80));
  }

  void _onTapUp(TapUpDetails _) {
    if (_longPressActive) return;
    _scaleCtrl.animateTo(0, duration: const Duration(milliseconds: 100));
  }

  void _onTapCancel() {
    if (_longPressActive) return;
    _scaleCtrl.animateTo(0, duration: const Duration(milliseconds: 100));
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _longPressActive = true;
    _isCancelling = false;
    HapticFeedback.heavyImpact();
    _scaleCtrl.animateTo(1.0, duration: const Duration(milliseconds: 120));
    widget.onRecordStart();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final shouldCancel =
        details.localOffsetFromOrigin.dx < _cancelThresholdDx;
    if (shouldCancel != _isCancelling) {
      HapticFeedback.lightImpact();
      setState(() => _isCancelling = shouldCancel);
    }
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _longPressActive = false;
    HapticFeedback.lightImpact();
    _scaleCtrl.animateTo(0, duration: const Duration(milliseconds: 150));
    if (_isCancelling) {
      setState(() => _isCancelling = false);
      widget.onRecordCancel();
    } else {
      widget.onRecordStop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleCtrl, _pulseCtrl]),
        builder: (context, _) {
          final isRecording = widget.isRecording;
          final isCancelling = _isCancelling;
          final bgColor = isCancelling
              ? Colors.grey.shade400
              : isRecording
                  ? Colors.red
                  : TeqColors.primary;
          final opacity = isRecording ? _pulseAnim.value : 1.0;

          return Transform.scale(
            scale: _scaleAnim.value,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRecording ? Icons.mic_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
