import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/moderation_service.dart';

/// Co-Host moderasyon bottom sheet'i.
/// Sadece Sustur / Susturmayı Kaldır / Yayından At — "Moderatör Yap" YOK.
class CoHostModSheet extends StatefulWidget {
  final int streamId;
  final String username;
  final bool isMuted;
  final VoidCallback onMuted;
  final VoidCallback onUnmuted;

  const CoHostModSheet({
    super.key,
    required this.streamId,
    required this.username,
    required this.isMuted,
    required this.onMuted,
    required this.onUnmuted,
  });

  @override
  State<CoHostModSheet> createState() => _CoHostModSheetState();
}

class _CoHostModSheetState extends State<CoHostModSheet> {
  bool _loading = false;
  String? _msg;
  bool _isError = false;
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.isMuted;
  }

  Future<void> _act(
    Future<void> Function() fn, {
    required String successMsg,
    VoidCallback? onSuccess,
  }) async {
    setState(() {
      _loading = true;
      _msg = null;
    });
    try {
      await fn();
      onSuccess?.call();
      if (mounted) {
        setState(() {
          _loading = false;
          _msg = successMsg;
          _isError = false;
        });
      }
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _msg = e.toString();
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '🛡 ${l.modTitle}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '@${widget.username}',
                style: const TextStyle(
                    color: Color(0xFF06B6D4),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),

          // Sustur / Susturmayı Kaldır
          if (!_isMuted)
            CoHostModBtn(
              icon: '🔇',
              label: l.modMute,
              color: const Color(0xFFD97706),
              loading: _loading,
              onTap: () => _act(
                () => ModerationService.mute(widget.streamId, widget.username),
                successMsg: '@${widget.username} susturuldu',
                onSuccess: () {
                  widget.onMuted();
                  setState(() => _isMuted = true);
                },
              ),
            )
          else
            CoHostModBtn(
              icon: '🔊',
              label: l.modUnmute,
              color: const Color(0xFF16A34A),
              loading: _loading,
              onTap: () => _act(
                () =>
                    ModerationService.unmute(widget.streamId, widget.username),
                successMsg: l.modUnmutedMsg,
                onSuccess: () {
                  widget.onUnmuted();
                  setState(() => _isMuted = false);
                },
              ),
            ),
          const SizedBox(height: 10),

          // Yayından At
          CoHostModBtn(
            icon: '🚫',
            label: l.modKick,
            color: const Color(0xFFEF4444),
            loading: _loading,
            onTap: () => _act(
              () => ModerationService.kick(widget.streamId, widget.username),
              successMsg: '@${widget.username} yayından atıldı',
            ),
          ),
          const SizedBox(height: 10),

          // İptal
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white12),
                ),
              ),
              child: Text(
                l.btnCancel,
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 14),
              ),
            ),
          ),

          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: _isError
                        ? const Color(0xFFF87171)
                        : const Color(0xFF4ADE80),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CoHostModBtn extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const CoHostModBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onTap,
        icon: Text(icon, style: const TextStyle(fontSize: 16)),
        label: Text(
          label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }
}
