import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web is not supported.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBV6l2Z_D_KHn9_tU6PtUrhBom3YY2AzVY',
    appId: '1:232766108005:android:1be15fe4cb2708a551b18c',
    messagingSenderId: '232766108005',
    projectId: 'teqlif-a24ee',
    storageBucket: 'teqlif-a24ee.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB4pHo_Pq3yTlsAsb0b1tJoO1wfipD6lUE',
    appId: '1:232766108005:ios:71bf8e062c4a16c051b18c',
    messagingSenderId: '232766108005',
    projectId: 'teqlif-a24ee',
    storageBucket: 'teqlif-a24ee.firebasestorage.app',
    iosBundleId: 'teqlif',
  );

}