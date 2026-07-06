/// A guard that prevents concurrent async function invocations.
///
/// Usage in a [StatefulWidget]:
/// ```dart
/// final _logoutGuard = OnceGuard();
///
/// onTap: () => _logoutGuard.run(() async {
///   await AuthService.logout();
/// }),
/// ```
class OnceGuard {
  bool _busy = false;

  /// Runs [fn] only if not already running. Subsequent calls while [fn] is
  /// in progress are silently discarded.
  Future<void> run(Future<void> Function() fn) async {
    if (_busy) return;
    _busy = true;
    try {
      await fn();
    } finally {
      _busy = false;
    }
  }

  /// Whether an operation is currently in progress.
  bool get isBusy => _busy;
}
