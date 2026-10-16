import 'package:flutter/material.dart';

import '../../../models/recording.dart';

class ActivityTimeline extends StatelessWidget {
  final List<ParticipantAnyAction> actions;
  final double? durationSecs;

  const ActivityTimeline({
    super.key,
    required this.actions,
    this.durationSecs,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: CustomPaint(
        painter: _TimelinePainter(
          actions: actions,
          durationSecs: durationSecs,
          context: context,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<ParticipantAnyAction> actions;
  final double? durationSecs;
  final BuildContext context;

  _TimelinePainter({
    required this.actions,
    required this.durationSecs,
    required this.context,
  });

  Color _colorFor(ParticipantActionType type, ColorScheme cs) {
    switch (type) {
      case ParticipantActionType.bid:
        return cs.primary;
      case ParticipantActionType.order:
        return cs.tertiary;
      case ParticipantActionType.gift:
        return const Color(0xFFE91E63);
      case ParticipantActionType.chat:
        return cs.outlineVariant;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cs = Theme.of(context).colorScheme;
    final trackPaint = Paint()
      ..color = cs.outlineVariant.withAlpha(80)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackPaint);

    final double maxOffset = durationSecs ??
        actions
            .where((a) => a.offsetSecs != null)
            .fold<double>(0.0, (m, a) => a.offsetSecs! > m ? a.offsetSecs! : m);

    if (maxOffset <= 0) return;

    for (final a in actions) {
      if (a.offsetSecs == null || a.offsetSecs! < 0) continue;
      final x = (a.offsetSecs! / maxOffset) * size.width;
      final paint = Paint()
        ..color = _colorFor(a.type, cs)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x.clamp(3, size.width - 3), cy), 4, paint);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.actions != actions || old.durationSecs != durationSecs;
}
