import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Required for modern FlutterFire web setup
import 'screens/landing_screen.dart';
import 'screens/not_found_screen.dart';
import 'services/url_strategy_helper.dart'
    if (dart.library.js_util) 'services/url_strategy_helper_web.dart';

void main() async {
  configureUrl();
  // Ensure the Flutter engine is fully initialized before talking to native plugins like Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase securely for your specific platform (Web, Android, iOS)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Boot up the application
  runApp(const ViGoApp());
}

class ViGoApp extends StatelessWidget {
  const ViGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ViGo - VIT Carpool',
      debugShowCheckedModeBanner: false, // Removes the red debug banner for a premium feel
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA), // A sleek off-white background
        useMaterial3: true, // Enables modern, rounded Material Design 3 components
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.indigo),
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      // Set the very first screen the user sees to your new cinematic landing page
      home: const LandingScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/404') {
          return MaterialPageRoute(builder: (context) => const NotFoundScreen(), settings: settings);
        }
        // Fallback for any unknown web path
        return MaterialPageRoute(
          builder: (context) => const NotFoundScreen(),
          settings: settings,
        );
      },
    );
  }
}