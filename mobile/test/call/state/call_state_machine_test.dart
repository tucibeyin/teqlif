import 'package:flutter_test/flutter_test.dart';
import 'package:teqlif/call/state/call_state_machine.dart';
import 'package:teqlif/call/state/call_status.dart';
import 'package:teqlif/call/state/call_role.dart';

void main() {
  group('CallStateMachine — self-transition', () {
    test('her state kendi kendine geçiş yapar (her role)', () {
      for (final status in CallStatus.values) {
        for (final role in CallRole.values) {
          expect(
            CallStateMachine.transition(current: status, next: status, role: role),
            equals(status),
            reason: 'self-transition her zaman geçerli | $status role=$role',
          );
        }
      }
    });
  });

  group('CallStateMachine — Caller transitions', () {
    test('idle → dialing geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.dialing, role: CallRole.caller),
        equals(CallStatus.dialing),
      );
    });

    test('idle → ringing geçersiz (caller-only idle)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.ringing, role: CallRole.caller),
        isNull,
      );
    });

    test('idle → waiting geçersiz (dialing atlanamaz)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.waiting, role: CallRole.caller),
        isNull,
      );
    });

    test('dialing → waiting geçerli (/start 200: callId geldi)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.dialing, next: CallStatus.waiting, role: CallRole.caller),
        equals(CallStatus.waiting),
      );
    });

    test('dialing → ended geçerli (HTTP hatası)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.dialing, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('waiting → connecting geçerli (call_accepted WS)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.waiting, next: CallStatus.connecting, role: CallRole.caller),
        equals(CallStatus.connecting),
      );
    });

    test('waiting → ended geçerli (cancel/error)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.waiting, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('waiting → rejected geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.waiting, next: CallStatus.rejected, role: CallRole.caller),
        equals(CallStatus.rejected),
      );
    });

    test('waiting → busy geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.waiting, next: CallStatus.busy, role: CallRole.caller),
        equals(CallStatus.busy),
      );
    });

    test('connecting → active geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.active, role: CallRole.caller),
        equals(CallStatus.active),
      );
    });

    test('connecting → ended geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('connecting → reconnecting geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.reconnecting, role: CallRole.caller),
        equals(CallStatus.reconnecting),
      );
    });

    test('active → ended geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.active, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('active → reconnecting geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.active, next: CallStatus.reconnecting, role: CallRole.caller),
        equals(CallStatus.reconnecting),
      );
    });

    test('reconnecting → active geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.active, role: CallRole.caller),
        equals(CallStatus.active),
      );
    });

    test('reconnecting → ended geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('ended → idle geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.idle, role: CallRole.caller),
        equals(CallStatus.idle),
      );
    });

    test('ended → dialing geçerli (yeni arama hemen başlatılabilir)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.dialing, role: CallRole.caller),
        equals(CallStatus.dialing),
      );
    });

    test('rejected → idle geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.rejected, next: CallStatus.idle, role: CallRole.caller),
        equals(CallStatus.idle),
      );
    });

    test('idle → permissionDenied geçerli (mic kontrolü dialing öncesi)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.permissionDenied, role: CallRole.caller),
        equals(CallStatus.permissionDenied),
      );
    });

    test('permissionDenied → ended geçerli (caller — _hangUpLocally uyumluluğu)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.permissionDenied, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });
  });

  group('CallStateMachine — Callee transitions', () {
    test('idle → ringing geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.ringing, role: CallRole.callee),
        equals(CallStatus.ringing),
      );
    });

    test('idle → dialing geçersiz (callee-only idle)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.dialing, role: CallRole.callee),
        isNull,
      );
    });

    test('ringing → connecting geçerli (accept)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ringing, next: CallStatus.connecting, role: CallRole.callee),
        equals(CallStatus.connecting),
      );
    });

    test('ringing → ended geçerli (caller cancel)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ringing, next: CallStatus.ended, role: CallRole.callee),
        equals(CallStatus.ended),
      );
    });

    test('ringing → missed geçerli (timeout)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ringing, next: CallStatus.missed, role: CallRole.callee),
        equals(CallStatus.missed),
      );
    });

    test('connecting → active geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.active, role: CallRole.callee),
        equals(CallStatus.active),
      );
    });

    test('connecting → ended geçerli (api_accept_error — race condition)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.ended, role: CallRole.callee),
        equals(CallStatus.ended),
      );
    });

    test('active → ended geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.active, next: CallStatus.ended, role: CallRole.callee),
        equals(CallStatus.ended),
      );
    });

    test('reconnecting → active geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.active, role: CallRole.callee),
        equals(CallStatus.active),
      );
    });

    test('ended → idle geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.idle, role: CallRole.callee),
        equals(CallStatus.idle),
      );
    });

    test('ended → dialing geçersiz (callee yeni arama bu rolde başlatamaz)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.dialing, role: CallRole.callee),
        isNull,
      );
    });

    test('idle → permissionDenied geçersiz (callee — mic kontrolü connecting\'de)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.permissionDenied, role: CallRole.callee),
        isNull,
      );
    });

    test('connecting → permissionDenied geçerli (callee — acceptCall mic izni yok)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.permissionDenied, role: CallRole.callee),
        equals(CallStatus.permissionDenied),
      );
    });

    test('permissionDenied → ended geçerli (callee — _hangUpLocally uyumluluğu)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.permissionDenied, next: CallStatus.ended, role: CallRole.callee),
        equals(CallStatus.ended),
      );
    });
  });

  group('CallStateMachine — Role null (crash recovery fallback)', () {
    test('idle → dialing geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.dialing, role: null),
        equals(CallStatus.dialing),
      );
    });

    test('idle → ringing geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.ringing, role: null),
        equals(CallStatus.ringing),
      );
    });

    test('dialing → waiting geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.dialing, next: CallStatus.waiting, role: null),
        equals(CallStatus.waiting),
      );
    });

    test('reconnecting → active geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.active, role: null),
        equals(CallStatus.active),
      );
    });
  });

  group('CallStateMachine — isActiveCallState', () {
    test('dialing aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.dialing), isTrue));
    test('waiting aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.waiting), isTrue));
    test('ringing aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.ringing), isTrue));
    test('connecting aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.connecting), isTrue));
    test('active aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.active), isTrue));
    test('reconnecting aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.reconnecting), isTrue));
    test('idle pasif', () => expect(CallStateMachine.isActiveCallState(CallStatus.idle), isFalse));
    test('ended pasif', () => expect(CallStateMachine.isActiveCallState(CallStatus.ended), isFalse));
    test('rejected pasif', () => expect(CallStateMachine.isActiveCallState(CallStatus.rejected), isFalse));
  });

  group('CallStateMachine — allowedTargets', () {
    test('caller idle için dialing ve permissionDenied', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.idle, CallRole.caller),
        equals({CallStatus.dialing, CallStatus.permissionDenied}),
      );
    });

    test('callee idle için sadece ringing', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.idle, CallRole.callee),
        equals({CallStatus.ringing}),
      );
    });

    test('null role idle için dialing ve ringing (union)', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.idle, null),
        containsAll([CallStatus.dialing, CallStatus.ringing]),
      );
    });

    test('caller dialing için waiting ve ended', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.dialing, CallRole.caller),
        containsAll([CallStatus.waiting, CallStatus.ended]),
      );
    });
  });
}
