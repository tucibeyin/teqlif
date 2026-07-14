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
  
  var pendingAcceptActions: [String: CXAnswerCallAction] = [:]
  
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
        let callkitChannel = FlutterMethodChannel(name: "com.teqlif/callkit",
                                                  binaryMessenger: registrar.messenger())
        callkitChannel.setMethodCallHandler({ [weak self]
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
          if call.method == "fulfillAccept" {
              if let args = call.arguments as? [String: Any],
                 let uuid = args["uuid"] as? String {
                  self?.pendingAcceptActions[uuid]?.fulfill()
                  self?.pendingAcceptActions.removeValue(forKey: uuid)
                  result(true)
              } else {
                  result(false)
              }
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
      
      // CallId'yi UUID'ye çeviriyoruz (Tıpkı Dart tarafında yaptığımız gibi)
      let padded = callId.padding(toLength: 32, withPad: "0", startingAt: 0)
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
      
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
          completion()
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
      print("[CallkitAppDelegate] onAccept called for \(call.uuid.uuidString)")
      // ACTION'ı hafızada tutuyoruz, hemen fulfill etmiyoruz (Bağlanıyor yazısı çıkacak).
      pendingAcceptActions[call.uuid.uuidString] = action
  }
  
  func onDecline(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
      action.fulfill()
  }
  
  func onEnd(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
      // Eğer arama sonlanmışsa ve önceden açık kalmış bir accept action varsa temizle
      pendingAcceptActions.removeValue(forKey: call.uuid.uuidString)
      action.fulfill()
  }
  
  func onTimeOut(_ call: flutter_callkit_incoming.Call) {
      pendingAcceptActions.removeValue(forKey: call.uuid.uuidString)
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
      print("[CallKit] didActivateAudioSession called")
  }
  
  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
      print("[CallKit] didDeactivateAudioSession called")
  }
  
  func providerDidReset() {
      // Eğer provider çökerse her şeyi serbest bırak
      for (_, action) in pendingAcceptActions {
          action.fulfill()
      }
      pendingAcceptActions.removeAll()
  }
}
