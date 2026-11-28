import 'package:flutter/material.dart';

/// Canlı yayın UI butonları için press animasyonu.
///
/// GestureDetector'ın sağlamadığı görsel geri bildirimi verir:
/// basışta scale 0.82 + opacity 0.65, bırakışta elastic bounce.
class LivePressBtn extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const LivePressBtn({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
  });

  @override
  State<LivePressBtn> createState() => _LivePressBtnState();
}

class _LivePressBtnState extends State<LivePressBtn> {
  bool _pressed = false;

  void _down(TapDownDetails _) => setState(() => _pressed = true);
  void _up(TapUpDetails _) => setState(() => _pressed = false);
  void _cancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      child: AnimatedScale(
        scale: _pressed ? 0.82 : 1.0,
        duration: Duration(milliseconds: _pressed ? 80 : 160),
        curve: _pressed ? Curves.easeIn : Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.65 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: widget.child,
        ),
      ),
    );
  }
}
