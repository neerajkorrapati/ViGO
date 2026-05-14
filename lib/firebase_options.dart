import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
   apiKey: "AIzaSyDjDNSZ8QY1BB1hCfMpomJWZfJm4eBIpwE",
  authDomain: "vigo1-d2128.firebaseapp.com",
  projectId: "vigo1-d2128",
  storageBucket: "vigo1-d2128.firebasestorage.app",
  messagingSenderId: "305617221299",
  appId: "1:305617221299:web:2fc7138ea1d240f6b562c6"

  );
}