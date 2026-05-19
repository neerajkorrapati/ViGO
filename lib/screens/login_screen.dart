import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  bool _isLoading = false;

  void _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await _auth.signInWithGoogle();
      // AuthGate will automatically detect the login and navigate.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A53FF).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car, size: 80, color: Color(0xFF1A53FF)),
              ),
              const SizedBox(height: 32),
              const Text(
                "Vi Go",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                "Exclusive carpool network\nfor students.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.5),
              ),
              const Spacer(),
              _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A53FF)))
                : ElevatedButton.icon(
                    onPressed: _handleGoogleSignIn,
                    icon: const Icon(Icons.login),
                    label: const Text("Continue with Google"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
              const SizedBox(height: 16),
              const Text(
                "Please use your institutional email.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}