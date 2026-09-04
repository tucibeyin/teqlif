import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_toast.dart';

void callPermissionToast(String? reason, TranslationPack loc) {
  final message = switch (reason) {
    'no_follow'     => loc.tOr('callReasonNoFollow', 'Takipleşin ya da mesajlaşma isteği gönderin.'),
    'pending'       => loc.tOr('callReasonPending', 'Mesaj isteği kabul edilince karşı taraf arama özelliğini açabilir.'),
    'call_disabled' => loc.tOr('callReasonCallDisabled', 'Karşı taraf arama özelliğini size karşı kapattı.'),
    _               => loc.tOr('callReasonNoFollow', 'Takipleşin ya da mesajlaşma isteği gönderin.'),
  };
  TeqToast.info(message);
}
