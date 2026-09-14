import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_bottom_sheet.dart';
import '../ui_library/foundation/teq_colors.dart';

enum AppPermissionResult { granted, denied, permanentlyDenied }

/// Uygulama genelinde donanım izinlerini (Kamera, Mikrofon, Galeri vb.)
/// merkezi olarak yöneten servis. Clean Architecture ve UI/UX standartlarına (TeqBottomSheet)
/// uygun olarak tasarlanmıştır.
class PermissionService {
  PermissionService._();

  /// Verilen [permissions] listesini işletim sisteminden (OS) ister.
  /// Eğer izinlerden herhangi biri reddedilirse veya kalıcı olarak reddedilmişse,
  /// ekrana [TeqBottomSheet] ile verilen [titleText], [bodyText] ve [iconData]'yı
  /// kullanarak bir uyarı çıkartır ve `false` döner.
  /// Bütün izinler verilmişse `true` döner.
  static Future<bool> requestPermissions(
    BuildContext context, {
    required List<Permission> permissions,
    required String titleText,
    required String bodyText,
    required IconData iconData,
  }) async {
    // 1. İzinleri OS'den iste
    final statuses = await permissions.request();

    // 2. Herhangi bir izin reddedilmiş mi kontrol et
    bool anyDenied = false;
    for (final status in statuses.values) {
      if (!status.isGranted) {
        anyDenied = true;
        break;
      }
    }

    if (!anyDenied) {
      return true;
    }

    // 3. UI Kontrolü: Ekrana uyarıyı bas ve false dön
    if (context.mounted) {
      final loc = ProviderScope.containerOf(context, listen: false)
          .read(localizationProvider);
      
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final iconColor = isDark ? TeqColors.textSecondaryDark : TeqColors.textSecondaryLight;
      final textColor = isDark ? TeqColors.textSecondaryDark : TeqColors.textSecondaryLight;

      TeqBottomSheet.show(
        context: context,
        title: titleText,
        child: Column(
          children: [
            Icon(iconData, size: 48, color: iconColor),
            const SizedBox(height: 16),
            Text(
              bodyText,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    return false;
  }

  /// Canlı yayın başlatırken Kamera ve Mikrofon izinlerini birlikte kontrol eder.
  /// Sadece ikisi birden onaylandığında `true` döner.
  static Future<bool> requestLiveStreamPermissions(BuildContext context) async {
    // Önce durumları alıp dinamik hata mesajı belirleyebiliriz (biri eksikse ona göre)
    // Ama `permissions.request()` topluca OS pop-uplarını çıkaracağı için,
    // reddedilenlere göre mesajı sonradan belirlemek daha zordur.
    // Şimdilik en kapsayıcı "Kamera ve mikrofon izni gerekli" mesajını kullanıyoruz.
    if (!context.mounted) return false;
    final loc = ProviderScope.containerOf(context, listen: false).read(localizationProvider);
    
    return requestPermissions(
      context,
      permissions: [Permission.camera, Permission.microphone],
      titleText: loc.t('livePermissionRequired'), // "Kamera ve mikrofon izni gerekli"
      bodyText: loc.tOr('liveBothPermissionDesc', 'Canlı yayın başlatabilmek için kamera ve mikrofon izinlerine ihtiyacımız var. Lütfen ayarlardan izin verin.'),
      iconData: Icons.videocam_off_outlined,
    );
  }
}
