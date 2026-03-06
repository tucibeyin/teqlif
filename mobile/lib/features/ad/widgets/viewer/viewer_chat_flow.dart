import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ad.dart';
import '../../controllers/live_arena_viewer_controller.dart';

class ViewerChatFlow extends ConsumerWidget {
  final AdModel ad;
  final double height;

  const ViewerChatFlow({
    super.key,
    required this.ad,
    required this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(
        viewerControllerProvider(ad).select((s) => s.messages));

    return Padding(
      padding:
          const EdgeInsets.only(left: 16, bottom: 8, right: 80),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0.0, 0.3, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: SizedBox(
          height: height,
          child: ListView.builder(
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[messages.length - 1 - index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: RichText(
                    text: TextSpan(children: [
                  TextSpan(
                      text: '${msg.senderName}: ',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white70,
                          fontSize: 13)),
                  TextSpan(
                      text: msg.text,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ])),
              );
            },
          ),
        ),
      ),
    );
  }
}
