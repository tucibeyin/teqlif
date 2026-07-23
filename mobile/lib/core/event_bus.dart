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
/// ProHubScreen bu event'i dinleyerek _loadCredits() çağırır.
class CreditsChangedEvent {
  const CreditsChangedEvent();
}
