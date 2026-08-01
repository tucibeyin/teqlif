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
    test('idle → calling geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.calling, role: CallRole.caller),
        equals(CallStatus.calling),
      );
    });

    test('idle → ringing geçersiz (caller-only idle)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.ringing, role: CallRole.caller),
        isNull,
      );
    });

    test('calling → connecting geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.calling, next: CallStatus.connecting, role: CallRole.caller),
        equals(CallStatus.connecting),
      );
    });

    test('calling → ended geçerli (cancel/error)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.calling, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('calling → rejected geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.calling, next: CallStatus.rejected, role: CallRole.caller),
        equals(CallStatus.rejected),
      );
    });

    test('calling → busy geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.calling, next: CallStatus.busy, role: CallRole.caller),
        equals(CallStatus.busy),
      );
    });

    test('connecting → connected geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.connected, role: CallRole.caller),
        equals(CallStatus.connected),
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

    test('connected → ended geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connected, next: CallStatus.ended, role: CallRole.caller),
        equals(CallStatus.ended),
      );
    });

    test('connected → reconnecting geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connected, next: CallStatus.reconnecting, role: CallRole.caller),
        equals(CallStatus.reconnecting),
      );
    });

    test('reconnecting → connected geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.connected, role: CallRole.caller),
        equals(CallStatus.connected),
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

    test('ended → calling geçerli (yeni arama hemen başlatılabilir)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.calling, role: CallRole.caller),
        equals(CallStatus.calling),
      );
    });

    test('rejected → idle geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.rejected, next: CallStatus.idle, role: CallRole.caller),
        equals(CallStatus.idle),
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

    test('idle → calling geçersiz (callee-only idle)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.calling, role: CallRole.callee),
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

    test('connecting → connected geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.connected, role: CallRole.callee),
        equals(CallStatus.connected),
      );
    });

    test('connecting → ended geçerli (api_accept_error — race condition)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connecting, next: CallStatus.ended, role: CallRole.callee),
        equals(CallStatus.ended),
      );
    });

    test('connected → ended geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.connected, next: CallStatus.ended, role: CallRole.callee),
        equals(CallStatus.ended),
      );
    });

    test('reconnecting → connected geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.connected, role: CallRole.callee),
        equals(CallStatus.connected),
      );
    });

    test('ended → idle geçerli', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.idle, role: CallRole.callee),
        equals(CallStatus.idle),
      );
    });

    test('ended → calling geçersiz (callee yeni arama hemen başlatamaz bu rolde)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.ended, next: CallStatus.calling, role: CallRole.callee),
        isNull,
      );
    });
  });

  group('CallStateMachine — Role null (crash recovery fallback)', () {
    test('idle → calling geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.calling, role: null),
        equals(CallStatus.calling),
      );
    });

    test('idle → ringing geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.idle, next: CallStatus.ringing, role: null),
        equals(CallStatus.ringing),
      );
    });

    test('reconnecting → connected geçerli (role unknown)', () {
      expect(
        CallStateMachine.transition(current: CallStatus.reconnecting, next: CallStatus.connected, role: null),
        equals(CallStatus.connected),
      );
    });
  });

  group('CallStateMachine — isActiveCallState', () {
    test('calling aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.calling), isTrue));
    test('ringing aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.ringing), isTrue));
    test('connecting aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.connecting), isTrue));
    test('connected aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.connected), isTrue));
    test('reconnecting aktif', () => expect(CallStateMachine.isActiveCallState(CallStatus.reconnecting), isTrue));
    test('idle pasif', () => expect(CallStateMachine.isActiveCallState(CallStatus.idle), isFalse));
    test('ended pasif', () => expect(CallStateMachine.isActiveCallState(CallStatus.ended), isFalse));
    test('rejected pasif', () => expect(CallStateMachine.isActiveCallState(CallStatus.rejected), isFalse));
  });

  group('CallStateMachine — allowedTargets', () {
    test('caller idle için sadece calling', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.idle, CallRole.caller),
        equals({CallStatus.calling}),
      );
    });

    test('callee idle için sadece ringing', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.idle, CallRole.callee),
        equals({CallStatus.ringing}),
      );
    });

    test('null role idle için calling ve ringing (union)', () {
      expect(
        CallStateMachine.allowedTargets(CallStatus.idle, null),
        containsAll([CallStatus.calling, CallStatus.ringing]),
      );
    });
  });
}
