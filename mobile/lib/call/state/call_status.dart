enum CallStatus {
  idle,
  dialing,     // caller: HTTP /start in-flight, no callId yet
  waiting,     // caller: callId received, waiting for callee to accept
  ringing,     // callee: incoming call, waiting for user action
  connecting,  // accepted — joining LiveKit room
  active,      // in call, audio flowing
  ended,
  rejected,
  missed,
  noAnswer,
  permissionDenied,
  busy,
  reconnecting,
}
