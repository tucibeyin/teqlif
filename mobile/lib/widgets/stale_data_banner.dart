import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';

/// Cache'den gelen eski veri gösterilirken ağ güncellemesi başarısız olduğunda
/// içerik alanının üstüne yerleştirilen ince uyarı şeridi.
///
/// Kullanım:
/// ```dart
/// if (_networkError && items.isNotEmpty)
///   StaleDataBanner(onRetry: _load),
/// ```
class StaleDataBanner extends ConsumerWidget {
  final VoidCallback onRetry;
  const StaleDataBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Material(
      color: Colors.orange.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 15, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc.t("staleDataBannerMessage"),
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                loc.t("btnRefresh"),
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
