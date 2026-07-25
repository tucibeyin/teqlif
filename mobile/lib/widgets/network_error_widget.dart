import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';

/// Sayfa yüklemesi başarısız olduğunda gösterilen standart "bağlantı yok" widget'ı.
///
/// Pull-to-refresh destekleyen ekranlarda ListView içine sarılı gelir;
/// diğerlerinde doğrudan Center içinde kullanılabilir.
///
/// Kullanım:
/// ```dart
/// if (_hasNetworkError)
///   NetworkErrorWidget(onRetry: _load)
/// ```
class NetworkErrorWidget extends ConsumerWidget {
  final VoidCallback onRetry;
  final bool scrollable;

  const NetworkErrorWidget({
    super.key,
    required this.onRetry,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 52, color: Color(0xFFD1D5DB)),
        const SizedBox(height: 14),
        Text(
          loc.t("errorNetworkTitle"),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          loc.t("errorNetworkMessage"),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(loc.t("btnRetry")),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );

    if (scrollable) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: content),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: content,
      ),
    );
  }
}
