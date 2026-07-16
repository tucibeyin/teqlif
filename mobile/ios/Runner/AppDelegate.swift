import Flutter
import UIKit
import UserNotifications
import PushKit
import flutter_callkit_incoming
import CallKit
import AVFAudio
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {

  // Flutter'a audioSessionActivated sinyali göndermek için kanal referansı.
  var callkitChannel: FlutterMethodChannel?
  // Retained CXCallController for foreground VoIP-push auto-dismiss transactions.
  private let _ckController = CXCallController()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self

    // Setup VOIP
    let mainQueue = DispatchQueue.main
    let voipRegistry: PKPushRegistry = PKPushRegistry(queue: mainQueue)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let registrar = self.registrar(forPlugin: "com.teqlif/callkit") {
        let channel = FlutterMethodChannel(name: "com.teqlif/callkit",
                                           binaryMessenger: registrar.messenger())
        self.callkitChannel = channel
        channel.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
          // fulfillAccept artık gerekmez — onAccept anında fulfill eder.
          // Bu handler geriye dönük uyumluluk için korunuyor (no-op).
          if call.method == "fulfillAccept" {
              result(true)
          } else {
              result(FlutterMethodNotImplemented)
          }
        })
    }

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // ── VoIP Token — Native Layer (WhatsApp pattern) ──────────────────────────
  //
  // Bu metod Flutter engine'den tamamen bağımsız çalışır.
  // PKPushRegistry callback'i app kapalıyken de tetiklenir; Keychain'den
  // auth token'ı okuyarak doğrudan URLSession ile backend'e kaydeder.

  private let kVoIPTokenKey = "teqlif_voip_token"   // UserDefaults backup
  private let kBackendURL   = "https://www.teqlif.com/api/auth/device-tokens"

  /// flutter_secure_storage Keychain'inden JWT auth token'ını okur.
  private func readAuthToken() -> String? {
    let query: [CFString: Any] = [
      kSecClass:            kSecClassGenericPassword,
      kSecAttrService:      "flutter_secure_storage",
      kSecAttrAccount:      "teqlif_token",
      kSecReturnData:       true,
      kSecMatchLimit:       kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Foundation.Data,
          let token = String(data: data, encoding: .utf8) else {
      return nil
    }
    return token
  }

  /// Token'ı backend'e URLSession ile gönderir — Flutter bridge gerektirmez.
  /// voipToken boş string ise backend token'ı DB'den temizler.
  private func sendVoIPTokenToBackend(_ voipToken: String) {
    guard let authToken = readAuthToken() else {
      print("[PushKit][Native] Auth token yok — token kaydedilemedi")
      return
    }
    guard let url = URL(string: kBackendURL) else { return }

    var req = URLRequest(url: url)
    req.httpMethod          = "POST"
    req.timeoutInterval     = 15
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = ["voip_token": voipToken]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
    req.httpBody = bodyData

    URLSession.shared.dataTask(with: req) { _, response, error in
      if let error = error {
        print("[PushKit][Native] Token kayıt hatası: \(error.localizedDescription)")
      } else if let http = response as? HTTPURLResponse {
        print("[PushKit][Native] Token kayıt yanıtı: \(http.statusCode) | token=\(voipToken.prefix(10))...")
      }
    }.resume()
  }

  // VoIP Push Token Updates
  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
      let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
      print("[PushKit] Token alındı: \(deviceToken.prefix(16))...")

      // 1. Flutter plugin'e bildir (Flutter bridge — engine açıksa çalışır)
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)

      // 2. UserDefaults yedek — uygulama açıldığında reconciliation için
      UserDefaults.standard.set(deviceToken, forKey: kVoIPTokenKey)

      // 3. Native HTTP: Flutter bridge bypass — uygulama kapalıyken de çalışır
      sendVoIPTokenToBackend(deviceToken)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
      print("[PushKit] Token geçersiz kılındı — backend'e silme isteği gönderiliyor")
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
      UserDefaults.standard.removeObject(forKey: kVoIPTokenKey)
      // Backend'e explicit silme isteği at (boş string → DB'den sil)
      sendVoIPTokenToBackend("")
  }

  // ── ISO8601 timestamp helper ─────────────────────────────────────────────────
  private func ts() -> String {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fmt.string(from: Date())
  }

  // Handle incoming pushes
  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
      print("[PushKit] VoIP Push Geldi!")
      guard type == .voIP else { return }
      
      let dictionary = payload.dictionaryPayload

      // APNs'ten gelen verileri alıyoruz
      let callId = dictionary["call_id"] as? String ?? dictionary["id"] as? String ?? ""
      let callerUsername = dictionary["caller_username"] as? String ?? dictionary["nameCaller"] as? String ?? "Bilinmeyen"
      let callerAvatar = dictionary["caller_avatar"] as? String ?? dictionary["avatar"] as? String ?? "https://i.pravatar.cc/100"
      let roomName = dictionary["room_name"] as? String ?? ""
      let callerId = dictionary["caller_id"] as? String ?? ""
      print("[CALL_PROCESS][\(ts())][PUSH] VoIP Push received | callId=\(callId) caller=\(callerUsername) roomName=\(roomName) callerId=\(callerId)")
      
      // CallId'yi UUID'ye çeviriyoruz (Dart _formatToUuid ile aynı: sola sıfır dolgulama)
      let padded = String(repeating: "0", count: max(0, 32 - callId.count)) + callId
      let start0 = padded.index(padded.startIndex, offsetBy: 0)
      let start8 = padded.index(padded.startIndex, offsetBy: 8)
      let start12 = padded.index(padded.startIndex, offsetBy: 12)
      let start16 = padded.index(padded.startIndex, offsetBy: 16)
      let start20 = padded.index(padded.startIndex, offsetBy: 20)
      let end32 = padded.index(padded.startIndex, offsetBy: 32)
      
      let uuidStr = "\(padded[start0..<start8])-\(padded[start8..<start12])-\(padded[start12..<start16])-\(padded[start16..<start20])-\(padded[start20..<end32])"
      
      let langCode = UserDefaults.standard.string(forKey: "flutter.app_locale_language_code") ?? "tr"
      var handleText = "Sesli Arama"
      switch langCode {
      case "en": handleText = "Voice Call"
      case "ar": handleText = "مكالمة صوتية"
      case "ru": handleText = "Голосовой звонок"
      default: handleText = "Sesli Arama"
      }
      
      let data = flutter_callkit_incoming.Data(id: uuidStr, nameCaller: callerUsername, handle: handleText, type: 0)
      data.avatar = callerAvatar
      data.extra = [
          "call_id": callId,
          "call_uuid": uuidStr,
          "caller_id": callerId,
          "caller_username": callerUsername,
          "caller_avatar": callerAvatar,
          "room_name": roomName
      ]

      // If app is already in foreground, WS + IncomingCallBar handles the call UI.
      // Apple requires reportNewIncomingCall for every VoIP push, so we call
      // showCallkitIncoming — but dismiss the CX call immediately inside the completion
      // block (fires once reportNewIncomingCall succeeds) to prevent the full-screen
      // CallKit UI from ever appearing. 300ms asyncAfter caused a visible flash; the
      // completion block eliminates it entirely.
      let appIsActive = UIApplication.shared.applicationState == .active
      let callUUID = UUID(uuidString: data.uuid)
      print("[CALL_PROCESS][\(ts())][PUSH] showCallkitIncoming | callId=\(callId) caller=\(callerUsername) appIsActive=\(appIsActive)")
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) { [weak self] in
          guard let self = self else { completion(); return }
          print("[CALL_PROCESS][\(self.ts())][PUSH] showCallkitIncoming completion | callId=\(callId) appIsActive=\(appIsActive)")
          completion()
          guard appIsActive, let uuid = callUUID else { return }
          // Dismiss synchronously after registration — no asyncAfter delay needed since
          // the completion block guarantees reportNewIncomingCall has already returned.
          let endAction = CXEndCallAction(call: uuid)
          let tx = CXTransaction(action: endAction)
          self._ckController.request(tx) { error in
              print("[CALL_PROCESS][\(self.ts())][PUSH] CallKit instant-dismiss | callId=\(callId) error=\(error?.localizedDescription ?? "none")")
          }
      }
  }

  // Uygulama açıkken gelen bildirimleri banner + badge + ses olarak göster
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  // Kullanıcı bildirime tıkladığında
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  // MARK: - CallkitIncomingAppDelegate Methods
  
  func onAccept(_ call: flutter_callkit_incoming.Call, _ action: CXAnswerCallAction) {
      // Apple CallKit contract: action.fulfill() → CallKit audio session aktive eder
      // → provider(_:didActivate:) → didActivateAudioSession → Flutter'a sinyal.
      // Dart'ın onayını beklemek UUID uyumsuzluğu doğurur; doğrudan fulfill et.
      print("[CALL_PROCESS][\(ts())][IN] onAccept | uuid=\(call.uuid.uuidString)")
      action.fulfill()
      print("[CALL_PROCESS][\(ts())][IN] action.fulfill() done → didActivateAudioSession expected next")
  }

  func onDecline(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
      print("[CALL_PROCESS][\(ts())][IN] onDecline | uuid=\(call.uuid.uuidString)")
      action.fulfill()
  }

  func onEnd(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
      print("[CALL_PROCESS][\(ts())][IN] onEnd | uuid=\(call.uuid.uuidString)")
      action.fulfill()
  }

  func onTimeOut(_ call: flutter_callkit_incoming.Call) {
      print("[CALL_PROCESS][\(ts())][IN] onTimeOut | uuid=\(call.uuid.uuidString)")
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
      // CallKit audio session hazır → Flutter'a bildir, setMicrophoneEnabled bekleyebilir.
      print("[CALL_PROCESS][\(ts())][HW] didActivateAudioSession → signalling Flutter via callkitChannel")
      DispatchQueue.main.async { [weak self] in
          let dispatchTs = ISO8601DateFormatter().string(from: Date())
          print("[CALL_PROCESS][\(dispatchTs)][HW] didActivateAudioSession: invokeMethod audioSessionActivated dispatched")
          self?.callkitChannel?.invokeMethod("audioSessionActivated", arguments: nil)
      }
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
      print("[CALL_PROCESS][\(ts())][HW] didDeactivateAudioSession")
  }

  func providerDidReset() {
      print("[CALL_PROCESS][\(ts())][IN] providerDidReset")
  }
}
