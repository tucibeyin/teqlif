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
          ValueListenableBuilder<int>(
            valueListenable: CallService.instance.visibleCallScreensCount,
            builder: (context, count, _) {
              if (count > 0) return const SizedBox.shrink();

              return ValueListenableBuilder<CallState>(
                valueListenable: CallService.instance.state,
                builder: (context, cs, _) {
                  if (cs.status != CallStatus.connected &&
                      cs.status != CallStatus.calling &&
                      cs.status != CallStatus.connecting) {
                    return const SizedBox.shrink();
                  }

                  final isConnecting = cs.status != CallStatus.connected;

                  return Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    left: 16,
                    right: 16,
                    child: SafeArea(
                      bottom: false,
                      child: GestureDetector(
                        onTap: () {
                          if (CallService.instance.visibleCallScreensCount.value > 0) return;
                          
                          final context = navigatorKey.currentContext;
                          if (context != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CallScreen(),
                                fullscreenDialog: true,
                              ),
                            );
                          }
                        },
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isConnecting ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.phone_in_talk,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Builder(
                                    builder: (innerContext) {
                                      try {
                                        final ctx = navigatorKey.currentContext ?? context;
                                        final l = AppLocalizations.of(ctx);
                                        return Text(
                                          l?.callReturnToActive ?? 'Aramaya dönmek için dokunun',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      } catch (_) {
                                        return const Text(
                                          'Aramaya dönmek için dokunun',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        );
                                      }
                                    }
                                  ),
                                ),
                                if (!isConnecting) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatElapsed(cs.elapsed),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ],
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
