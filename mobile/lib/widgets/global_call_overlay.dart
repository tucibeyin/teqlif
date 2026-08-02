import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/call_service.dart';
import '../screens/call_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../config/api.dart';
import 'package:cached_network_image/cached_network_image.dart';

void _uiLog(String component, String event, String detail) {
  debugPrint('[UI_CALL][$component][${DateTime.now().toIso8601String()}] $event | $detail');
}

class GlobalCallOverlay extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const GlobalCallOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  ConsumerState<GlobalCallOverlay> createState() => _GlobalCallOverlayState();
}

class _GlobalCallOverlayState extends ConsumerState<GlobalCallOverlay> {
  final _cs = CallService.instance;
  bool _prevPillVisible = false;
  bool _permDialogShown = false;

  @override
  void initState() {
    super.initState();
    _cs.isCallScreenVisible.addListener(_onVisibilityChange);
    _cs.state.addListener(_onStateChange);
    _cs.elapsed.addListener(_onElapsedChange);
    _cs.isSpeaker.addListener(_onAdapterStateChange);
  }

  @override
  void dispose() {
    _cs.isCallScreenVisible.removeListener(_onVisibilityChange);
    _cs.state.removeListener(_onStateChange);
    _cs.elapsed.removeListener(_onElapsedChange);
    _cs.isSpeaker.removeListener(_onAdapterStateChange);
    super.dispose();
  }

  void _checkPillTransition() {
    final isVisible = _cs.isCallScreenVisible.value;
    final cs = _cs.state.value;
    final shouldShow = !isVisible &&
        (cs.status == CallStatus.active || cs.status == CallStatus.connecting);
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
    _handleCallerPermissionDenied();
    setState(() {});
  }

  // §7.3 Kural 5 — caller mic denied: no screen was open, overlay shows feedback.
  void _handleCallerPermissionDenied() {
    final cs = _cs.state.value;
    if (cs.status != CallStatus.ended) return;
    if (cs.endReason != EndReason.permissionDenied) return;
    if (_cs.isCallScreenVisible.value) return;
    if (_permDialogShown) return;

    _permDialogShown = true;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      _permDialogShown = false;
      return;
    }

    if (cs.permPermanentlyDenied) {
      final loc = ref.read(localizationProvider);
      showDialog<void>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: Text(loc.t('callPermissionDenied')),
          content: Text(loc.t('voicePermissionDenied')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(loc.t('btnCancel')),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dctx);
                await openAppSettings();
              },
              child: Text(loc.t('navSettings')),
            ),
          ],
        ),
      ).whenComplete(() => _permDialogShown = false);
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(ref.read(localizationProvider).t('callPermissionDenied')),
          duration: const Duration(seconds: 3),
        ),
      );
      _permDialogShown = false;
    }
  }

  void _onElapsedChange() => setState(() {});

  void _onAdapterStateChange() {
    if (mounted) setState(() {});
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final isVisible = _cs.isCallScreenVisible.value;
    final cs = _cs.state.value;
    final isSpeaker = _cs.isSpeaker.value;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (!isVisible &&
              (cs.status == CallStatus.active ||
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
                                        ? loc.t("callConnecting")
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
                                  _cs.setSpeaker(!isSpeaker);
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSpeaker
                                        ? Colors.white
                                        : Colors.white24,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSpeaker
                                        ? Icons.volume_up
                                        : Icons.volume_down,
                                    color: isSpeaker
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
