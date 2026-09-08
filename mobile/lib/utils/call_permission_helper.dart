import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_toast.dart';

void callPermissionToast(String? reason, TranslationPack loc) {
  final message = switch (reason) {
    'no_follow'     => loc.t('callReasonNoFollow'),
    'pending'       => loc.t('callReasonPending'),
    'call_disabled' => loc.t('callReasonCallDisabled'),
    'user_busy'     => loc.t('callReasonBusy'),
    'blocked'       => loc.t('callReasonBlocked'),
    'declined'      => loc.t('callReasonDeclined'),
    _               => loc.t('callReasonNoFollow'),
  };
  TeqToast.info(message);
}
