import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../config/theme.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/version_service.dart';

class SoftUpdateDialog extends StatelessWidget {
  const SoftUpdateDialog({super.key});

  Future<void> _launchStore() async {
    final url = Platform.isIOS ? VersionService.iosStoreUrl : VersionService.androidStoreUrl;
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: AppColors.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.system_update_rounded, size: 48, color: kPrimary),
            const SizedBox(height: 16),
            Text(
              l.softUpdateTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l.softUpdateMessage,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _launchStore();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                child: Text(l.softUpdateUpdateNow),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l.softUpdateLater,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
