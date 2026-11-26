import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../services/notif_ws_service.dart';
import '../services/push_notification_service.dart';

// ── In-app notification data ──────────────────────────────────────────────────

class InAppNotif {
  final int id;
  final String notifType;
  final String title;
  final String? body;
  final int? relatedId;

  const InAppNotif({
    required this.id,
    required this.notifType,
    required this.title,
    this.body,
    this.relatedId,
  });

  factory InAppNotif.fromWs(Map<String, dynamic> data) => InAppNotif(
        id: (data['id'] as num?)?.toInt() ?? 0,
        notifType: data['notif_type'] as String? ?? '',
        title: data['title'] as String? ?? '',
        body: data['body'] as String?,
        relatedId: (data['related_id'] as num?)?.toInt(),
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class InAppNotifNotifier extends Notifier<InAppNotif?> {
  @override
  InAppNotif? build() => null;

  void show(InAppNotif notif) => state = notif;
  void dismiss() => state = null;
}

final inAppNotifProvider =
    NotifierProvider<InAppNotifNotifier, InAppNotif?>(() => InAppNotifNotifier());

// ── Overlay widget ────────────────────────────────────────────────────────────

/// Wraps the app root; shows an in-app notification banner when
/// [inAppNotifProvider] holds a value.  Auto-dismisses after 4 seconds.
/// Place it in the MaterialApp.builder chain, same level as IncomingCallOverlay.
class InAppNotifBanner extends ConsumerStatefulWidget {
  final Widget child;
  const InAppNotifBanner({super.key, required this.child});

  @override
  ConsumerState<InAppNotifBanner> createState() => _InAppNotifBannerState();
}

class _InAppNotifBannerState extends ConsumerState<InAppNotifBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  Timer? _autoDismiss;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _wsSub = ref.read(notifWsServiceProvider).messageStream.stream.listen(_onWsMessage);
  }

  void _onWsMessage(Map<String, dynamic> data) {
    if (data['type'] != 'notification') return;
    // Also emit to PushNotificationService.notificationStream for badge refresh.
    PushNotificationService.badgeRefreshNeeded.add(null);
    ref.read(inAppNotifProvider.notifier).show(InAppNotif.fromWs(data));
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _wsSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _show() {
    _autoDismiss?.cancel();
    _ctrl.forward(from: 0);
    _autoDismiss = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    _ctrl.reverse().then((_) => ref.read(inAppNotifProvider.notifier).dismiss());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InAppNotif?>(inAppNotifProvider, (_, next) {
      if (next != null) _show();
    });

    final notif = ref.watch(inAppNotifProvider);
    return Stack(
      children: [
        widget.child,
        if (notif != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: SlideTransition(
              position: _slide,
              child: _BannerCard(notif: notif, onDismiss: _dismiss),
            ),
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  final InAppNotif notif;
  final VoidCallback onDismiss;
  const _BannerCard({required this.notif, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.card(context);
    final border  = AppColors.border(context);
    final primary = AppColors.textPrimary(context);
    final secondary = AppColors.textSecondary(context);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_outlined,
                    size: 18, color: Color(0xFF0EA5E9)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(notif.title,
                        style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (notif.body != null && notif.body!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(notif.body!,
                          style: TextStyle(color: secondary, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 16, color: secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
