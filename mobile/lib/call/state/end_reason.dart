enum EndReason {
  normal,           // user_call_end (her iki taraf)
  rejected,         // callee reddetti
  missed,           // ring timeout — server bildirdi
  noAnswer,         // caller 30s timer doldu
  busy,             // /start 409 — callee meşgul
  permissionDenied, // mic izni reddedildi
  error,            // LiveKit/API kalıcı hata
}
