import 'call_role.dart';
import 'call_status.dart';

// V2.0 VoIP mimarisine göre role-aware transition tablosu.
// Her transition sadece bir role için geçerliyse yalnızca o tabloda bulunur.
// Shared state'ler (connecting, active, ended, reconnecting) her iki tabloda da var.
//
// Step 3'te terminal state'ler (rejected/missed/noAnswer/busy/permissionDenied)
// ended + EndReason olarak absorbe edilecek.

class CallStateMachine {
  CallStateMachine._();

  // ── Caller transition tablosu ──────────────────────────────────────────────
  // dialing: HTTP /start in-flight, callId yok.
  // waiting: callId geldi, callee'yi bekliyoruz.

  static const Map<CallStatus, Set<CallStatus>> _callerTransitions = {
    CallStatus.idle: {
      CallStatus.dialing,
      CallStatus.ended, // mic izni reddi → ended (endReason=permissionDenied)
    },
    CallStatus.dialing: {
      CallStatus.waiting, // /start → 200: callId + token geldi
      CallStatus.ended,   // /start HTTP hatası
      CallStatus.idle,
    },
    CallStatus.waiting: {
      CallStatus.connecting, // call_accepted WS eventi
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.connecting: {
      CallStatus.active,
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.active: {
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.reconnecting: {
      CallStatus.active,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ended: {
      CallStatus.idle,
      CallStatus.dialing, // arama biter bitmez yeni arama başlatılabilir
    },
  };

  // ── Callee transition tablosu ──────────────────────────────────────────────

  static const Map<CallStatus, Set<CallStatus>> _calleeTransitions = {
    CallStatus.idle: {
      CallStatus.ringing,
    },
    CallStatus.ringing: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.connecting: {
      CallStatus.active,
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.active: {
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.reconnecting: {
      CallStatus.active,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ended: {
      CallStatus.idle,
    },
  };

  // ── Role bilinmiyorsa fallback (crash recovery, uygulama yeniden açılış) ──
  // Caller + callee tablolarının union'ı — en geniş izin seti.

  static const Map<CallStatus, Set<CallStatus>> _unknownRoleTransitions = {
    CallStatus.idle: {
      CallStatus.dialing,
      CallStatus.ringing,
      CallStatus.ended, // caller mic izni reddi
    },
    CallStatus.dialing: {
      CallStatus.waiting,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.waiting: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ringing: {
      CallStatus.connecting,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.connecting: {
      CallStatus.active,
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.active: {
      CallStatus.ended,
      CallStatus.reconnecting,
      CallStatus.idle,
    },
    CallStatus.reconnecting: {
      CallStatus.active,
      CallStatus.ended,
      CallStatus.idle,
    },
    CallStatus.ended: {
      CallStatus.idle,
      CallStatus.dialing,
    },
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Geçerli bir transition ise [next] state'i döner, geçersizse null.
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
    return status == CallStatus.dialing ||
        status == CallStatus.waiting ||
        status == CallStatus.ringing ||
        status == CallStatus.connecting ||
        status == CallStatus.active ||
        status == CallStatus.reconnecting;
  }
}
