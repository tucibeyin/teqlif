import Flutter
import UIKit
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    
    // EKLENEN KISIM 1: Apple'dan cihazı bildirimlere kaydetmesini istiyoruz
    application.registerForRemoteNotifications()
      
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
    
  // EKLENEN KISIM 2: Apple Token VERİRSE bu fonksiyon çalışır
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
      let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
      let token = tokenParts.joined()
      print("🍏 [NATIVE APNS] Apple Token Başarıyla Alındı: \(token)")
      super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // EKLENEN KISIM 3: Apple Token VERMEYİ REDDEDERSE bu fonksiyon çalışır ve sebebi söyler
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
      print("🍎 [NATIVE APNS HATA] Apple Token VERMEDİ! Gerçek Neden: \(error.localizedDescription)")
      super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}