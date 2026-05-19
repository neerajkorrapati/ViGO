import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // 1. Waiting for Firebase to initialize
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. User is NOT logged in -> Show Login
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // 3. User IS logged in. Check if they finished Onboarding.
        return FutureBuilder<bool>(
          future: AuthService().isProfileComplete(snapshot.data!.uid),
          builder: (context, profileSnapshot) {
            
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // 4. They have a profile -> Go to Home
            if (profileSnapshot.data == true) {
              return const HomeScreen();
            } 
            
            // 5. They logged in but no profile -> Go to Onboarding
            else {
              return const OnboardingScreen();
            }
          },
        );
      },
    );
  }
}