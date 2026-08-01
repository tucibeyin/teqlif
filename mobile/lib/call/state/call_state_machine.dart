import 'call_role.dart';
import 'call_status.dart';

// V2.0 VoIP mimarisine göre role-aware transition tablosu.
// Her transition sadece bir role için geçerliyse yalnızca o tabloda bulunur.
// Shared state'ler (connecting, connected, ended, reconnecting) her iki tabloda da var.
//
// Step 2'de state isimleri V2.0'a uygun hale getirilecek:
//   calling   → dialing + waiting (ayrılacak)
//   connected → active (rename)
//   rejected/missed/noAnswer/busy/permissionDenied → ended + EndReason (Step 3)

class CallStateMachine {
  CallStateMachine._();

  // ── Caller transition tablosu ──────────────────────────────────────────────
  // calling: V2.0'da dialing + waiting. Step 2'de ikiye bölünecek.

  static const Map<CallStatus, Set<CallStatus>> _callerTransitions = {
    CallStatus.idle: {
      CallStatus.calling,
    },
    CallStatus.calling: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.rejected,   // Step 3'te ended+reason'a absorbe edilecek
      CallStatus.missed,
      CallStatus.noAnswer,
      CallStatus.busy,
      CallStatus.idle,
    },
    CallStatus.connecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.connected: {
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.reconnecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ended: {
      CallStatus.idle,
      CallStatus.calling, // arama biter bitmez yeni arama başlatılabilir
    },
    // Terminal state'ler — tek geçiş: idle'a dön
    CallStatus.rejected: {CallStatus.idle},
    CallStatus.missed: {CallStatus.idle},
    CallStatus.noAnswer: {CallStatus.idle},
    CallStatus.busy: {CallStatus.idle},
    CallStatus.permissionDenied: {CallStatus.idle},
  };

  // ── Callee transition tablosu ──────────────────────────────────────────────

  static const Map<CallStatus, Set<CallStatus>> _calleeTransitions = {
    CallStatus.idle: {
      CallStatus.ringing,
    },
    CallStatus.ringing: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.missed,   // ring timeout
      CallStatus.rejected, // kullanıcı reddetti
      CallStatus.idle,
    },
    CallStatus.connecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.connected: {
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.reconnecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ended: {
      CallStatus.idle,
    },
    CallStatus.rejected: {CallStatus.idle},
    CallStatus.missed: {CallStatus.idle},
    CallStatus.permissionDenied: {CallStatus.idle},
  };

  // ── Role bilinmiyorsa fallback (crash recovery, uygulama yeniden açılış) ──
  // Caller + callee tablolarının union'ı — en geniş izin seti.

  static const Map<CallStatus, Set<CallStatus>> _unknownRoleTransitions = {
    CallStatus.idle: {
      CallStatus.calling,
      CallStatus.ringing,
    },
    CallStatus.calling: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.rejected,
      CallStatus.missed,
      CallStatus.noAnswer,
      CallStatus.busy,
      CallStatus.idle,
    },
    CallStatus.ringing: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.missed,
      CallStatus.rejected,
      CallStatus.idle,
    },
    CallStatus.connecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.connected: {
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.reconnecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ended: {
      CallStatus.idle,
      CallStatus.calling,
    },
    CallStatus.rejected: {CallStatus.idle},
    CallStatus.missed: {CallStatus.idle},
    CallStatus.noAnswer: {CallStatus.idle},
    CallStatus.busy: {CallStatus.idle},
    CallStatus.permissionDenied: {CallStatus.idle},
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Geçerli bir transition ise [next] state'i döner, geçersizse null.
  /// Çağıran: null gelirse state değiştirmez ve loglar.
  /// [role] null ise en geniş izin seti (fallback) kullanılır.
  static CallStatus? transition({
    required CallStatus current,
    required CallStatus next,
    required CallRole? role,
  }) {
    if (current == next) return next; // self-transition her zaman geçerli

    final table = switch (role) {
      CallRole.caller => _callerTransitions,
      CallRole.callee => _calleeTransitions,
      null => _unknownRoleTransitions,
    };

    final allowed = table[current] ?? const {};
    return allowed.contains(next) ? next : null;
  }

  /// Bu state için izin verilen hedef state'lerin listesi.
  static Set<CallStatus> allowedTargets(CallStatus current, CallRole? role) {
    final table = switch (role) {
      CallRole.caller => _callerTransitions,
      CallRole.callee => _calleeTransitions,
      null => _unknownRoleTransitions,
    };
    return table[current] ?? const {};
  }

  /// Aktif arama gerektiren state mi? WS lock ve wakelock kararlarında kullanılır.
  static bool isActiveCallState(CallStatus status) {
    return status == CallStatus.calling ||
        status == CallStatus.ringing ||
        status == CallStatus.connecting ||
        status == CallStatus.connected ||
        status == CallStatus.reconnecting;
  }
}
