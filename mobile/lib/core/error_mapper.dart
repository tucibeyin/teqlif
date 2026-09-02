import '../core/app_exception.dart';
import '../services/localization_service.dart';

/// Hata nesnelerini kullanıcıya gösterilecek lokalize string'e dönüştürür.
/// Show vs Log politikası: AppException.shouldCapture flag'i üzerinden yürür.
class ErrorMapper {
  ErrorMapper._();

  static String toMessage(Object error, TranslationPack loc) {
    if (error is NetworkException) {
      return loc.t('errorNetworkMessage');
    }

    if (error is AppException) {
      return _fromAppException(error, loc);
    }

    // Upload servisi string-tabanlı HTTP hataları fırlatır
    final s = error.toString();
    if (s.contains('HTTP 413')) return loc.t('uploadErrorTooLarge');
    if (s.contains('HTTP 502') ||
        s.contains('HTTP 503') ||
        s.contains('HTTP 504')) return loc.t('uploadErrorServerBusy');
    if (s.contains('HTTP 401') || s.contains('HTTP 403')) {
      return loc.t('uploadErrorAuthExpired');
    }

    return loc.t('errorGenericRetry');
  }

  static String map(Object error, TranslationPack loc) => toMessage(error, loc);

  static bool shouldLog(Object error) {
    if (error is AppException) return error.shouldCapture;
    return true;
  }

  static String _fromAppException(AppException e, TranslationPack loc) {
    // Kod bazlı eşleştirme — tüm bilinen backend hata kodları burada
    switch (e.code) {
      case 'INVALID_PASSWORD':
        return loc.t('errorInvalidPassword');
      case 'INVALID_CREDENTIALS':
      case 'UNAUTHORIZED':
        return loc.t('apiErrInvalidCredentials');
      case 'RATE_LIMIT_EXCEEDED':
      case 'RATE_LIMITED':
      case 'BID_RATE_LIMIT':
        return loc.t('errorTooFast');
      case 'FOLLOWERS_LIST_PRIVATE':
      case 'FOLLOWING_LIST_PRIVATE':
        return loc.t('errFollowListPrivate');
      case 'OFFER_FORBIDDEN':
        return loc.t('errOfferForbidden');
      case 'MESSAGING_FORBIDDEN':
        return loc.t('errMessagingForbidden');
      case 'FILE_TOO_LARGE':
        return loc.t('errFileTooLarge');
      case 'AUDIO_TOO_LARGE':
        return loc.t('errAudioTooLarge');
      case 'UNSUPPORTED_AUDIO_FORMAT':
        return loc.t('errUnsupportedAudioFormat');
      case 'INVALID_IMAGE_FORMAT':
        return loc.t('errInvalidImageFormat');
      case 'INVALID_VIDEO_FORMAT':
        return loc.t('errInvalidVideoFormat');
      case 'VIDEO_TOO_LONG':
        return loc.t('errVideoTooLong');
      case 'UNSUPPORTED_FILE_TYPE':
        return loc.t('errUnsupportedFileType');
      case 'MEDIA_EMPTY':
        return loc.t('errMediaEmpty');
      case 'FORBIDDEN':
      case 'CAPTCHA_FAILED':
        return loc.t('errorCaptchaFailed');
      case 'CONTENT_POLICY_VIOLATION':
        return loc.t('errorContentPolicy');
      case 'PROVINCE_REQUIRED':
        return loc.t('errProvinceRequired');
      case 'INVALID_CONDITION':
        return loc.t('errInvalidCondition');
      case 'INVALID_PRICE':
        return loc.t('errInvalidPrice');
      case 'LISTING_TITLE_REQUIRED':
        return loc.t('fieldListingTitleHint');
      case 'INSUFFICIENT_FUNDS_PRO':
        return loc.t('apiErrorInsufficientFundsPro', {'cost': '5'});
      case 'INSUFFICIENT_FUNDS_STD':
        return loc.t('apiErrorInsufficientFundsStd', {'cost': '5'});
      case 'AI_SERVICE_BUSY':
        return loc.t('apiErrorAiServiceBusy');
      case 'AI_SERVICE_TIMEOUT':
        return loc.t('apiErrorAiServiceTimeout');
    }

    // HTTP status bazlı fallback
    if (e.statusCode >= 500) return loc.t('errorServerBusy');
    if (e.statusCode == 401) return loc.t('errorSessionExpired');

    // Backend'den gelen mesajı doğrudan göster (4xx validation mesajları)
    if (e.message.isNotEmpty && e.message != 'ERR_UNKNOWN') return e.message;

    return loc.t('errorGenericRetry');
  }
}
