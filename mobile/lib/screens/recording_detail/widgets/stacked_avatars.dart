import 'package:flutter/material.dart';

class StackedAvatars extends StatelessWidget {
  final List<String?> avatarUrls;
  final int maxVisible;
  final double size;

  const StackedAvatars({
    super.key,
    required this.avatarUrls,
    this.maxVisible = 5,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final visible = avatarUrls.take(maxVisible).toList();
    final overflow = avatarUrls.length - maxVisible;
    final total = visible.length + (overflow > 0 ? 1 : 0);

    return SizedBox(
      width: size + (total - 1) * size * 0.6,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * size * 0.6,
              child: _avatar(context, visible[i]),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * size * 0.6,
              child: _overflowBadge(context, overflow),
            ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, String? url) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.5,
        ),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(context))
          : _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) => Icon(
        Icons.person,
        size: size * 0.6,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  Widget _overflowBadge(BuildContext context, int count) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.secondaryContainer,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: TextStyle(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
