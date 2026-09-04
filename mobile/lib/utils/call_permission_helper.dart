import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_toast.dart';

void callPermissionToast(String? reason, TranslationPack loc) {
  final message = switch (reason) {
    'no_follow'     => loc.tOr('callReasonNoFollow', 'Takipleşin ya da mesaj gönderin'),
    'pending'       => loc.tOr('callReasonPending', 'İstek kabul edilince arama açılabilir'),
    'call_disabled' => loc.tOr('callReasonCallDisabled', 'Karşı taraf aramayı kapattı'),
    _               => loc.tOr('callReasonNoFollow', 'Takipleşin ya da mesaj gönderin'),
  };
  TeqToast.info(message);
}
