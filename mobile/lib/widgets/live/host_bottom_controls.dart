import 'package:flutter/material.dart';

/// Canlı yayın host ekranı — medya kontrol butonları.
///
/// Mikrofon aç/kapat, kamera aç/kapat ve kamera çevirme
/// butonlarını içerir. Tamamen stateless'tır; durum ekran
/// widget'ında tutulur, değişiklikler callback ile bildirilir.
class HostBottomControls extends StatelessWidget {
  final bool micEnabled;
  final bool cameraEnabled;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;

  const HostBottomControls({
    super.key,
    required this.micEnabled,
    required this.cameraEnabled,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlBtn(
          key: const Key('host_btn_mikrofon_toggle'),
          icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
          active: micEnabled,
          onTap: onToggleMic,
        ),
        const SizedBox(width: 8),
        _ControlBtn(
          key: const Key('host_btn_kamera_toggle'),
          icon: cameraEnabled
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          active: cameraEnabled,
          onTap: onToggleCamera,
        ),
        const SizedBox(width: 8),
        _ControlBtn(
          key: const Key('host_btn_kamera_cevir'),
          icon: Icons.flip_camera_ios_rounded,
          active: true,
          onTap: onSwitchCamera,
        ),
      ],
    );
  }
}

/// Tek bir dairesel kontrol butonu — sadece bu dosyada kullanılır.
class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ControlBtn({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? Colors.black54 : Colors.red.withOpacity(0.75),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Colors.white30 : Colors.transparent,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
