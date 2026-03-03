import 'dart:math';
import 'package:flutter/material.dart';

class FloatingReaction {
  final String id;
  final String emoji;
  FloatingReaction({required this.id, required this.emoji});
}

class FloatingReactionsOverlay extends StatefulWidget {
  final List<FloatingReaction> reactions;

  const FloatingReactionsOverlay({Key? key, required this.reactions}) : super(key: key);

  @override
  State<FloatingReactionsOverlay> createState() => _FloatingReactionsOverlayState();
}

class _FloatingReactionsOverlayState extends State<FloatingReactionsOverlay> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: widget.reactions.map((r) => _FloatingEmojiWidget(key: ValueKey(r.id), emoji: r.emoji)).toList(),
      ),
    );
  }
}

class _FloatingEmojiWidget extends StatefulWidget {
  final String emoji;

  const _FloatingEmojiWidget({Key? key, required this.emoji}) : super(key: key);

  @override
  State<_FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<_FloatingEmojiWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bottomAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _horizontalAnimation;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    
    _bottomAnimation = Tween<double>(begin: 80, end: 400).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    
    // Slight random horizontal drift
    final double drift = (_random.nextDouble() - 0.5) * 100;
    _horizontalAnimation = Tween<double>(begin: 20, end: 20 + drift).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          bottom: _bottomAnimation.value,
          right: _horizontalAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Text(widget.emoji, style: const TextStyle(fontSize: 32)),
          ),
        );
      },
    );
  }
}

class ReactionButtons extends StatelessWidget {
  final Function(String) onReact;
  final bool isVertical;
  
  const ReactionButtons({Key? key, required this.onReact, this.isVertical = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: isVertical ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: ['❤️', '👍', '👏'].map((emoji) => Padding(
        padding: EdgeInsets.only(
          bottom: isVertical ? 12 : 0,
          right: isVertical ? 0 : 12,
        ),
        child: GestureDetector(
          onTap: () => onReact(emoji),
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0,4))
              ]
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
        ),
      )).toList(),
    );
  }
}
