import 'package:flutter/material.dart';
import 'ride_list_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // --- UPDATED: Using Logo instead of Text in the Top Left ---
        title: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Image.network(
            "/vigo_full_logo.jpeg",
            height: 50, // Perfectly scaled for the header
            fit: BoxFit.contain,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 120.0 : 24.0),
          child: Column(
            children: [
              // Hero Section
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                      children: [
                        const Text(
                          "Your Campus,\nConnected.",
                          style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -2),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "Stop overpaying for cabs. Match with VITians, split the fare, and travel smart...",
                          
                          style: TextStyle(fontSize: 20, color: Colors.black.withValues(alpha: 0.6), height: 1.6),
                          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        ElevatedButton(
                          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RideListScreen())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Explore Rides →", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  if (isDesktop) const SizedBox(width: 80),
                  if (isDesktop) 
                    // This is the larger version in the body
                    Expanded(child: Image.network("/vigo_full_logo.jpeg", fit: BoxFit.contain)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}