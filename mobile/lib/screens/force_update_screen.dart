import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';

// Uygulama mağazada yayınlandıktan sonra buraya gerçek store ID'leri yazılmalı.
const _kAndroidStoreUrl =
    'https://play.google.com/store/apps/details?id=com.teqlif.teqlif_mobile';
// iOS App Store ID'si (mağazada yayınlanınca güncellenecek):
const _kIosStoreUrl = 'https://apps.apple.com/app/id0000000000';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  Future<void> _openStore() async {
    final uri = Uri.parse(Platform.isIOS ? _kIosStoreUrl : _kAndroidStoreUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Mağaza açılamazsa sessizce devam et
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false, // geri tuşu devre dışı
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / ikon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kPrimary.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: kPrimary,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 32),

                // Başlık
                Text(
                  l.updateRequiredTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 14),

                // Açıklama
                Text(
                  l.updateRequiredDesc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),

                // Güncelle butonu
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openStore,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l.updateRequiredBtn),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
