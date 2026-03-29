import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../services/connectivity_service.dart';

/// Bağlantı durumunu dinler; çevrimdışıyken ince bir uyarı şeridi gösterir.
/// Geçişler AnimatedSize ile pürüzsüzdür.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(isConnectedProvider);

    // Bağlantı durumu henüz bilinmiyorsa gizle (ilk frame titremesi önlenir).
    final isOnline = connectivity.valueOrNull ?? true;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: isOnline
          ? const SizedBox.shrink()
          : _BannerContent(),
    );
  }
}

class _BannerContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFB91C1C), // kırmızı-700
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.offlineBannerMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
