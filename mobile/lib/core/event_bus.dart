import 'dart:async';

/// Dart tarafında global olay güdümlü mimari için temel EventBus
class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final StreamController<dynamic> _streamController = StreamController.broadcast();

  /// Olayı dinlemek isteyenler için Stream'i döner
  Stream<T> on<T>() {
    if (T == dynamic) {
      return _streamController.stream as Stream<T>;
    } else {
      return _streamController.stream.where((event) => event is T).cast<T>();
    }
  }

  /// Olay fırlatır
  void fire(dynamic event) {
    _streamController.add(event);
  }

  /// Kaynakları temizler
  void dispose() {
    _streamController.close();
  }
}

final eventBus = EventBus();

// -- Domain Events --
class AuthErrorEvent {
  final String message;
  AuthErrorEvent(this.message);
}

class ValidationErrorEvent {
  final Map<String, dynamic> errors;
  ValidationErrorEvent(this.errors);
}

/// Herhangi bir işlem sonucunda Pro kredi sayıları değiştiğinde fırlatılır.
/// SubscriptionToolsScreen bu event'i dinleyerek _loadCredits() çağırır.
class CreditsChangedEvent {
  const CreditsChangedEvent();
}

/// İlan aktif/pasif durumu değiştiğinde fırlatılır.
/// _MyListingsScreenState bu event'i dinleyerek listesini günceller.
class ListingStatusChangedEvent {
  final int listingId;
  final bool isActive;
  const ListingStatusChangedEvent({required this.listingId, required this.isActive});
}

/// Kullanıcı tier'ı değiştiğinde (satın alma / iptal) fırlatılır.
/// Profile, Ayarlar ve teqlif Araçları ekranları bu event'i dinleyerek
/// anlık güncelleme yapar.
class UserTypeChangedEvent {
  final String userType;
  const UserTypeChangedEvent(this.userType);
}

/// E-posta veya telefon doğrulama durumu değiştiğinde fırlatılır.
/// Ayarlar ekranındaki "Bilgilerim" satırı bu event'i dinleyerek
/// uyarı ikonunu anlık gösterir/gizler.
class UserVerificationChangedEvent {
  final bool emailVerified;
  final bool phoneVerified;
  const UserVerificationChangedEvent({
    required this.emailVerified,
    required this.phoneVerified,
  });
}

/// Teqlik → yayın dakikası dönüşümü başarıyla tamamlandığında fırlatılır.
/// WalletScreen bakiyeyi ve bonus dakikaları anlık günceller.
class WalletConversionSuccessEvent {
  final int spentTeqlik;
  final int addedMinutes;
  final int newBalance;
  final int newBonusMinutes;

  const WalletConversionSuccessEvent({
    required this.spentTeqlik,
    required this.addedMinutes,
    required this.newBalance,
    required this.newBonusMinutes,
  });
}
