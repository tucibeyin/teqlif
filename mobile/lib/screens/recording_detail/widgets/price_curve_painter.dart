import 'package:flutter/material.dart';

import '../../../models/recording.dart';

class PriceCurvePainter extends StatelessWidget {
  final RecordingAuction auction;
  final double height;

  const PriceCurvePainter({
    super.key,
    required this.auction,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final validBids = auction.bids
        .where((b) => b.offsetSecs != null && b.offsetSecs! >= 0)
        .toList()
      ..sort((a, b) => a.offsetSecs!.compareTo(b.offsetSecs!));

    if (validBids.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '${validBids.length} teklif',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _CurvePainter(bids: validBids, context: context),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<RecordingBid> bids;
  final BuildContext context;

  _CurvePainter({required this.bids, required this.context});

  @override
  void paint(Canvas canvas, Size size) {
    if (bids.length < 2) return;

    final cs = Theme.of(context).colorScheme;
    final minOffset = bids.first.offsetSecs!;
    final maxOffset = bids.last.offsetSecs!;
    final rangeOffset = maxOffset - minOffset;
    if (rangeOffset <= 0) return;

    final amounts = bids.map((b) => b.amount).toList();
    final minAmount = amounts.reduce((a, b) => a < b ? a : b);
    final maxAmount = amounts.reduce((a, b) => a > b ? a : b);
    final rangeAmount = maxAmount - minAmount;
    if (rangeAmount <= 0) return;

    Offset toPoint(RecordingBid b) {
      final x = ((b.offsetSecs! - minOffset) / rangeOffset) * size.width;
      final y = size.height -
          ((b.amount - minAmount) / rangeAmount) * (size.height - 8) - 4;
      return Offset(x, y);
    }

    final fillPath = Path();
    final points = bids.map(toPoint).toList();
    fillPath.moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withAlpha(80),
            cs.primary.withAlpha(10),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePath = Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = cs.primary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      points.last,
      4,
      Paint()..color = cs.primary,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.bids != bids;
}
