enum CallStatus {
  idle,
  calling, // outgoing — waiting for answer (V2.0: dialing + waiting, Step 2'de ayrılacak)
  ringing, // incoming — waiting for our action
  connecting, // accepted — joining LiveKit room
  connected, // in call (V2.0: active, Step 2'de rename edilecek)
  ended,
  rejected,
  missed,
  noAnswer,
  permissionDenied,
  busy,
  reconnecting,
}
