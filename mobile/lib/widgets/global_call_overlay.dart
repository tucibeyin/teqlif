import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../screens/call_screen.dart';
import '../l10n/app_localizations.dart';

class GlobalCallOverlay extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const GlobalCallOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          child,
          ValueListenableBuilder<bool>(
            valueListenable: CallService.instance.isCallScreenVisible,
            builder: (context, isVisible, _) {
              if (isVisible) return const SizedBox.shrink();

              return ValueListenableBuilder<CallState>(
                valueListenable: CallService.instance.state,
                builder: (context, cs, _) {
                  if (cs.status != CallStatus.connected &&
                      cs.status != CallStatus.connecting) {
                    return const SizedBox.shrink();
                  }

                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: GestureDetector(
                            onTap: () {
                              final ctx = navigatorKey.currentContext;
                              if (ctx != null) {
                                if (CallService.instance.isCallScreenVisible.value) return;
                                CallService.instance.isCallScreenVisible.value = true;
                                Navigator.of(ctx).push(
                                  MaterialPageRoute(
                                    settings: const RouteSettings(
                                      name: '/call_screen',
                                    ),
                                    builder: (_) => const CallScreen(),
                                    fullscreenDialog: true,
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Left: Icon + Timer
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.call,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Builder(
                                        builder: (innerContext) {
                                          try {
                                            final ctx =
                                                navigatorKey.currentContext ??
                                                context;
                                            final l = AppLocalizations.of(ctx);
                                            return Text(
                                              cs.status == CallStatus.connecting
                                                  ? (l?.callConnecting ??
                                                        'Connecting...')
                                                  : _formatElapsed(cs.elapsed),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            );
                                          } catch (_) {
                                            return Text(
                                              cs.status == CallStatus.connecting
                                                  ? 'Connecting...'
                                                  : _formatElapsed(cs.elapsed),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),

                                  // Right: End Call Button
                                  GestureDetector(
                                    onTap: () => CallService.instance.endCall(),
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.call_end,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
