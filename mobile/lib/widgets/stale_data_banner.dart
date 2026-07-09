import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Cache'den gelen eski veri gösterilirken ağ güncellemesi başarısız olduğunda
/// içerik alanının üstüne yerleştirilen ince uyarı şeridi.
///
/// Kullanım:
/// ```dart
/// if (_networkError && items.isNotEmpty)
///   StaleDataBanner(onRetry: _load),
/// ```
class StaleDataBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const StaleDataBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
                l.staleDataBannerMessage,
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
                l.btnRefresh,
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
