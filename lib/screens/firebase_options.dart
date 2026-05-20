import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAnvnH9LBUJ71H5TafxukiJEjiikg74K6k',
    appId: '1:1051773163800:web:8c8c8c8c8c8c8c8c8c8c8c',
    messagingSenderId: '1051773163800',
    projectId: 'kidora-9e74f',
    authDomain: 'kidora-9e74f.firebaseapp.com',
    storageBucket: 'kidora-9e74f.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAnvnH9LBUJ71H5TafxukiJEjiikg74K6k',
    appId: '1:1051773163800:android:8c8c8c8c8c8c8c8c8c8c8c',
    messagingSenderId: '1051773163800',
    projectId: 'kidora-9e74f',
    storageBucket: 'kidora-9e74f.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAnvnH9LBUJ71H5TafxukiJEjiikg74K6k',
    appId: '1:1051773163800:ios:8c8c8c8c8c8c8c8c8c8c8c',
    messagingSenderId: '1051773163800',
    projectId: 'kidora-9e74f',
    storageBucket: 'kidora-9e74f.appspot.com',
    iosBundleId: 'com.example.kidoraApp',
  );
}
