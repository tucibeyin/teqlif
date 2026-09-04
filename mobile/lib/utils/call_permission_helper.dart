import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_toast.dart';

void callPermissionToast(String? reason, TranslationPack loc) {
  final message = switch (reason) {
    'no_follow'     => loc.tOr('callReasonNoFollow', 'Aramak için takipleşmeniz gerekiyor'),
    'call_disabled' => loc.tOr('callReasonCallDisabled', 'Karşı taraf aramaya izin vermemiş'),
    _               => loc.tOr('callReasonNoFollow', 'Aramak için takipleşmeniz gerekiyor'),
  };
  TeqToast.info(message);
}
