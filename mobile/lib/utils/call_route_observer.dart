import 'package:flutter/material.dart';
import '../services/call_service.dart';

void _uiLog(String component, String event, String detail) {
  debugPrint('[UI_CALL][$component][${DateTime.now().toIso8601String()}] $event | $detail');
}

/// Navigator stack'i dinleyerek CallScreen görünürlüğünü tek otorite olarak yönetir.
/// CallScreen.initState / dispose artık bu flag'a dokunmaz.
/// addPostFrameCallback KULLANILMAZ — didPush/didPop synchronous olarak tetiklenir,
/// bu nedenle flag anında güncellenir ve overlay'in frame-gecikme bug'ı ortadan kalkar.
class CallRouteObserver extends NavigatorObserver {
  static const _callScreenName = '/call_screen';
  static const _incomingScreenName = '/incoming_call_screen';

  void _setVisible(bool value) {
    if (CallService.instance.isCallScreenVisible.value != value) {
      CallService.instance.isCallScreenVisible.value = value;
      _uiLog('ROUTE', 'VISIBILITY_CHANGE', 'isCallScreenVisible=$value callId=${CallService.instance.state.value.callId}');
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name == _callScreenName || name == _incomingScreenName) {
      _setVisible(true);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final prevName = previousRoute?.settings.name;
    // Sadece bir call ekranına dönülüyorsa visible kalır; yoksa false.
    _setVisible(prevName == _callScreenName || prevName == _incomingScreenName);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final name = newRoute?.settings.name;
    _setVisible(name == _callScreenName || name == _incomingScreenName);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    final name = route.settings.name;
    if (name == _callScreenName || name == _incomingScreenName) {
      final prevName = previousRoute?.settings.name;
      _setVisible(prevName == _callScreenName || prevName == _incomingScreenName);
    }
  }
}
