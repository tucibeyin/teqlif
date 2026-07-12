import 'package:flutter/material.dart';
import '../services/call_service.dart';

class CallRouteObserver extends NavigatorObserver {
  void _updateCallScreenVisibility(Route<dynamic>? route) {
    if (route == null) return;
    
    if (route is! ModalRoute) return;

    final name = route.settings.name;
    final isVisible = (name == '/call_screen' || name == '/incoming_call_screen');
    
    if (CallService.instance.isCallScreenVisible.value != isVisible) {
      CallService.instance.isCallScreenVisible.value = isVisible;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateCallScreenVisibility(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateCallScreenVisibility(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateCallScreenVisibility(newRoute);
  }
}
