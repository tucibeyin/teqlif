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

  private let kVoIPTokenKey    = "teqlif_voip_token"   // UserDefaults backup
  private let kBackendURL      = "https://www.teqlif.com/api/auth/device-tokens"
  private let kRefreshURL      = "https://www.teqlif.com/api/auth/refresh"
  private let kAuthTokenKey    = "teqlif_token"
  private let kRefreshTokenKey = "teqlif_refresh_token"

  /// flutter_secure_storage Keychain'inden verilen key'e ait değeri okur.
  private func readKeychainValue(_ key: String) -> String? {
    let query: [CFString: Any] = [
      kSecClass:       kSecClassGenericPassword,
      kSecAttrService: "flutter_secure_storage",
      kSecAttrAccount: key as CFString,
      kSecReturnData:  true,
      kSecMatchLimit:  kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Foundation.Data,
          let value = String(data: data, encoding: .utf8) else { return nil }
    return value
  }

  /// flutter_secure_storage formatında Keychain'e değer yazar (update veya add).
  private func saveKeychainValue(_ key: String, value: String) {
    guard let data = value.data(using: .utf8) else { return }
    let query: [CFString: Any] = [
      kSecClass:       kSecClassGenericPassword,
      kSecAttrService: "flutter_secure_storage",
      kSecAttrAccount: key as CFString,
    ]
    let attrs: [CFString: Any] = [kSecValueData: data]
    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData] = data
      SecItemAdd(addQuery as CFDictionary, nil)
    }
  }

  private func readAuthToken()    -> String? { readKeychainValue(kAuthTokenKey) }
  private func readRefreshToken() -> String? { readKeychainValue(kRefreshTokenKey) }

  /// 401 alındığında refresh token ile yeni access token alır, Keychain'e yazar
  /// ve VoIP token kaydını bir kez daha dener.
  private func refreshAuthTokenAndRetry(voipToken: String) {
    guard let refreshToken = readRefreshToken() else {
      print("[PushKit][Native] Refresh token yok — retry yapılamıyor")
      return
    }
    guard let url = URL(string: kRefreshURL) else { return }

    var req = URLRequest(url: url)
    req.httpMethod      = "POST"
    req.timeoutInterval = 15
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["refresh_token": refreshToken]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
    req.httpBody = bodyData

    URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
      guard let self = self else { return }
      guard error == nil,
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let data = data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let newAccess = json["access_token"] as? String else {
        print("[PushKit][Native] Token refresh başarısız — VoIP token kaydı iptal")
        return
      }
      self.saveKeychainValue(self.kAuthTokenKey, value: newAccess)
      if let newRefresh = json["refresh_token"] as? String {
        self.saveKeychainValue(self.kRefreshTokenKey, value: newRefresh)
      }
      print("[PushKit][Native] Token refresh başarılı — VoIP token kaydı yeniden deneniyor")
      self.sendVoIPTokenToBackend(voipToken)
    }.resume()
  }

  /// Token'ı backend'e URLSession ile gönderir — Flutter bridge gerektirmez.
  /// 401 alınırsa refresh token ile bir kez retry yapar.
  /// voipToken boş string ise backend token'ı DB'den temizler.
  private func sendVoIPTokenToBackend(_ voipToken: String) {
    guard let authToken = readAuthToken() else {
      print("[PushKit][Native] Auth token yok — token kaydedilemedi")
      return
    }
    guard let url = URL(string: kBackendURL) else { return }

    var req = URLRequest(url: url)
    req.httpMethod      = "POST"
    req.timeoutInterval = 15
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = ["voip_token": voipToken]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
    req.httpBody = bodyData

    URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
      if let error = error {
        print("[PushKit][Native] Token kayıt hatası: \(error.localizedDescription)")
      } else if let http = response as? HTTPURLResponse {
        print("[PushKit][Native] Token kayıt yanıtı: \(http.statusCode) | token=\(voipToken.prefix(10))...")
        if http.statusCode == 401 {
          print("[PushKit][Native] 401 → token refresh deneniyor")
          self?.refreshAuthTokenAndRetry(voipToken: voipToken)
        }
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
      let callId        = dictionary["call_id"] as? String ?? dictionary["id"] as? String ?? ""
      let callerUsername = dictionary["caller_username"] as? String ?? dictionary["nameCaller"] as? String ?? "Bilinmeyen"
      let callerAvatar  = dictionary["caller_avatar"] as? String ?? dictionary["avatar"] as? String ?? "https://i.pravatar.cc/100"
      let roomName      = dictionary["room_name"] as? String ?? ""
      let callerId      = dictionary["caller_id"] as? String ?? ""
      // Self-contained payload: callee_token + livekit_url artık VoIP push içinde geliyor.
      // Dart tarafı bunları extra'dan okuyarak HTTP fetch'i atlayabilir.
      let livekitUrl   = dictionary["livekit_url"] as? String ?? ""
      let calleeToken  = dictionary["callee_token"] as? String ?? ""
      print("[CALL_PROCESS][\(ts())][PUSH] VoIP Push received | callId=\(callId) caller=\(callerUsername) roomName=\(roomName) callerId=\(callerId) hasCalleeToken=\(!calleeToken.isEmpty)")
      
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
          "call_id":        callId,
          "call_uuid":      uuidStr,
          "caller_id":      callerId,
          "caller_username": callerUsername,
          "caller_avatar":  callerAvatar,
          "room_name":      roomName,
          "livekit_url":    livekitUrl,   // self-contained → Dart HTTP fetch'ini atlar
          "callee_token":   calleeToken,  // self-contained → pre-connect hemen başlar
      ]

      // Apple requires reportNewIncomingCall for every VoIP push regardless of app state.
      // When app is foreground, WS + IncomingCallBar already handles the call UI, so we
      // dismiss the native CallKit screen immediately after reportNewIncomingCall completes.
      // saveEndCall uses provider.reportCall directly (no CXCallController round-trip),
      // which is ~67ms faster than the CXEndCallAction transaction path.
      // Capture BEFORE showCallkitIncoming so CallKit UI appearance (inactive transition) can't race.
      let appIsActive = UIApplication.shared.applicationState == .active
      // Pass to Flutter via extra so Dart doesn't have to re-check lifecycle (which is already
      // inactive by the time CallEventActionCallIncoming fires).
      data.extra?["app_was_foreground"] = appIsActive

      print("[CALL_PROCESS][\(ts())][PUSH] showCallkitIncoming | callId=\(callId) caller=\(callerUsername) appIsActive=\(appIsActive)")
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) { [weak self] in
          guard let self = self else { completion(); return }
          print("[CALL_PROCESS][\(self.ts())][PUSH] showCallkitIncoming completion | callId=\(callId) appIsActive=\(appIsActive)")
          completion()
          guard appIsActive else { return }
          // provider.reportCall(reason: .unanswered) — synchronous, no delegate callback
          // chain. callManager.addCall already ran (inside reportNewIncomingCall completion
          // before this block), so the UUID is registered and saveEndCall succeeds.
          print("[CALL_PROCESS][\(self.ts())][PUSH] CallKit instant-dismiss (saveEndCall) | callId=\(callId)")
          SwiftFlutterCallkitIncomingPlugin.sharedInstance?.saveEndCall(data.uuid, 3)
      }
  }

  // Uygulama açıkken gelen bildirimleri banner + badge + ses olarak göster
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Suppress incoming_call FCM notification — VoIP PushKit / CallKit handles it natively.
    // Prevents a duplicate banner from appearing alongside the CallKit UI (or IncomingCallBar).
    let userInfo = notification.request.content.userInfo
    if (userInfo["type"] as? String) == "incoming_call" {
      print("[PUSH] willPresent: incoming_call FCM suppressed (VoIP handles it)")
      completionHandler([])
      return
    }
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
