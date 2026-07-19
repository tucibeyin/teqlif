import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../screens/call_screen.dart';
import '../l10n/app_localizations.dart';
import '../config/api.dart';
import 'package:cached_network_image/cached_network_image.dart';

void _uiLog(String component, String event, String detail) {
  debugPrint('[UI_CALL][$component][${DateTime.now().toIso8601String()}] $event | $detail');
}

class GlobalCallOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const GlobalCallOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<GlobalCallOverlay> createState() => _GlobalCallOverlayState();
}

class _GlobalCallOverlayState extends State<GlobalCallOverlay> {
  final _cs = CallService.instance;
  bool _prevPillVisible = false;

  @override
  void initState() {
    super.initState();
    _cs.isCallScreenVisible.addListener(_onVisibilityChange);
    _cs.state.addListener(_onStateChange);
    _cs.elapsed.addListener(_onElapsedChange);
  }

  @override
  void dispose() {
    _cs.isCallScreenVisible.removeListener(_onVisibilityChange);
    _cs.state.removeListener(_onStateChange);
    _cs.elapsed.removeListener(_onElapsedChange);
    super.dispose();
  }

  void _checkPillTransition() {
    final isVisible = _cs.isCallScreenVisible.value;
    final cs = _cs.state.value;
    final shouldShow = !isVisible &&
        (cs.status == CallStatus.connected || cs.status == CallStatus.connecting);
    if (shouldShow != _prevPillVisible) {
      _prevPillVisible = shouldShow;
      if (shouldShow) {
        _uiLog('PILL', 'SHOW', 'callId=${cs.callId} user=${cs.otherUsername} status=${cs.status.name}');
      } else {
        _uiLog('PILL', 'HIDE', 'callId=${cs.callId} status=${cs.status.name} isScreenVisible=$isVisible');
      }
    }
  }

  void _onVisibilityChange() {
    _checkPillTransition();
    setState(() {});
  }

  void _onStateChange() {
    _checkPillTransition();
    setState(() {});
  }

  void _onElapsedChange() => setState(() {});

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = _cs.isCallScreenVisible.value;
    final cs = _cs.state.value;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (!isVisible &&
              (cs.status == CallStatus.connected ||
                  cs.status == CallStatus.connecting))
            Positioned(
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
                          final ctx = widget.navigatorKey.currentContext;
                          if (ctx != null) {
                            if (_cs.isCallScreenVisible.value) return;
                            _uiLog('PILL', 'TAP', 'callId=${_cs.state.value.callId} user=${_cs.state.value.otherUsername}');
                            _cs.preventCallScreenAutoOpen.value = false;
                            _cs.isCallScreenVisible.value = true;
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (cs.otherAvatar != null) ...[
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.white24,
                                  backgroundImage: cs.otherAvatar!.isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          imgUrl(cs.otherAvatar!))
                                      : null,
                                  child: cs.otherAvatar!.isEmpty &&
                                          cs.otherUsername != null
                                      ? Text(
                                          cs.otherUsername!
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (cs.otherUsername != null)
                                    Text(
                                      cs.otherUsername!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    cs.status == CallStatus.connecting
                                        ? (AppLocalizations.of(context)
                                                ?.callConnecting ??
                                            'Connecting...')
                                        : _formatElapsed(_cs.elapsed.value),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 20),
                              GestureDetector(
                                onTap: () {
                                  _cs.setSpeaker(!cs.isSpeaker);
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.isSpeaker
                                        ? Colors.white
                                        : Colors.white24,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    cs.isSpeaker
                                        ? Icons.volume_up
                                        : Icons.volume_down,
                                    color: cs.isSpeaker
                                        ? Colors.black87
                                        : Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  _uiLog('PILL', 'END_TAP', 'callId=${_cs.state.value.callId} user=${_cs.state.value.otherUsername}');
                                  _cs.endCall();
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.call_end,
                                    color: Colors.white,
                                    size: 20,
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
            ),
        ],
      ),
    );
  }
}
