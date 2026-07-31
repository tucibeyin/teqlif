import 'package:flutter/material.dart';
import '../../config/app_colors.dart';

/// Yorum metni 2 satırı aşıyorsa genişletme oku gösterir.
/// 2 satır veya daha kısa metinlerde ok göstermez.
class ExpandableComment extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const ExpandableComment({super.key, required this.text, this.style});

  @override
  State<ExpandableComment> createState() => _ExpandableCommentState();
}

class _ExpandableCommentState extends State<ExpandableComment> {
  bool _expanded = false;

  static const int _maxCollapsedLines = 2;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ??
        TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary(context),
          height: 1.4,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _maxCollapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = tp.didExceedMaxLines;

        if (!overflows) {
          return Text(widget.text, style: style);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Text(
                widget.text,
                style: style,
                maxLines: _expanded ? null : _maxCollapsedLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textTertiary(context),
                  size: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
