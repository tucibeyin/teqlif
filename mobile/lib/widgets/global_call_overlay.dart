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
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Material(
                            type: MaterialType.transparency,
                            child: GestureDetector(
                              onTap: () {
                                debugPrint('[CALL_FLOW] [${DateTime.now().toIso8601String()}] [UI] GlobalCallOverlay body tapped. Returning to CallScreen.');
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
                                  horizontal: 12,
                                  vertical: 8,
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Timer / Connecting Text
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
                                    const SizedBox(width: 16),
                                    // End Call Button
                                    GestureDetector(
                                      onTap: () {
                                        debugPrint('[CALL_FLOW] [${DateTime.now().toIso8601String()}] [UI] GlobalCallOverlay END CALL button tapped.');
                                        CallService.instance.endCall();
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
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
