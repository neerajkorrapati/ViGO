import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/ride_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDjDNSZ8QY1BB1hCfMpomJWZfJm4eBIpwE",
  authDomain: "vigo1-d2128.firebaseapp.com",
  projectId: "vigo1-d2128",
  storageBucket: "vigo1-d2128.firebasestorage.app",
  messagingSenderId: "305617221299",
  appId: "1:305617221299:web:2fc7138ea1d240f6b562c6"
    ),
  );
  runApp(const VigoApp());
}

class VigoApp extends StatelessWidget {
  const VigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const RideListScreen(),
    );
  }
} 