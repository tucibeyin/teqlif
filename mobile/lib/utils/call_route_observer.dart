import 'package:flutter/material.dart';
import '../services/call_service.dart';

class CallRouteObserver extends NavigatorObserver {
  void _updateCallScreenVisibility(Route<dynamic>? route) {
    debugPrint('[DEBUG_UI] CallRouteObserver: didPush/Pop/Replace triggered. Route=$route, name=${route?.settings.name}');
    if (route == null) return;
    if (route is! ModalRoute) return;

    final name = route.settings.name;
    if (name == null) return;

    final isVisible = (name == '/call_screen' || name == '/incoming_call_screen');
    debugPrint('[DEBUG_UI] CallRouteObserver: name=$name -> evaluated isVisible=$isVisible');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[DEBUG_UI] CallRouteObserver post-frame: updating isCallScreenVisible.value = $isVisible (was ${CallService.instance.isCallScreenVisible.value})');
      if (CallService.instance.isCallScreenVisible.value != isVisible) {
        CallService.instance.isCallScreenVisible.value = isVisible;
      }
    });
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
