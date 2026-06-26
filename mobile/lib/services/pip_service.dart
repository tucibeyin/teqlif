import 'package:flutter/material.dart';
import '../widgets/live/pip_video_widget.dart';

class PipService {
  static OverlayEntry? _entry;

  static void showPip(BuildContext context) {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: (_) => const PipVideoWidget());
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void hidePip() {
    _entry?.remove();
    _entry = null;
  }

  static bool get isVisible => _entry != null;
}
