import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // Background image on the right
            Positioned(
              left: MediaQuery.of(context).size.width * 0.35 > 400
                  ? MediaQuery.of(context).size.width * 0.35
                  : 400,
              right: 0,
              top: 0,
              bottom: 0,
              child: Image.asset(
                'web/assets/404_desktop.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            
            // White cover on the left for text and buttons
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width * 0.45 > 460
                  ? MediaQuery.of(context).size.width * 0.45
                  : 460,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Vigo logo
                    Image.network(
                      "/vigo_full_logo.jpeg",
                      height: 50,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 50),
                    
                    // 404 Text
                    Text(
                      "404",
                      style: GoogleFonts.instrumentSans(
                        fontSize: 100,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A53FF),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Headline
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.instrumentSans(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                          height: 1.25,
                        ),
                        children: const [
                          TextSpan(text: "Looks like this\nride took a "),
                          TextSpan(
                            text: "wrong turn.",
                            style: TextStyle(color: Color(0xFF1A53FF)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Body text
                    Text(
                      "The page you're looking for\ncan't be found. Let's get you\nback on the road.",
                      style: GoogleFonts.instrumentSans(
                        fontSize: 16,
                        color: const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Take me home button
                    SizedBox(
                      height: 48,
                      width: 220,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A53FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                        },
                        icon: const Icon(Icons.home_outlined, size: 20),
                        label: const Text(
                          "Take me home",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Go back button
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1A53FF),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacementNamed(context, '/');
                        }
                      },
                      icon: const Icon(Icons.arrow_back, size: 20),
                      label: const Text(
                        "Go back",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Mobile View
      return Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // Background image containing logo and map
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              bottom: 140,
              child: Image.asset(
                'web/assets/404_mobile.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            
            // Transparent cover for the bottom to overlay functional buttons on top of design
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: const Color(0xFFF9F9FB),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Take me home button
                    SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A53FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                        },
                        icon: const Icon(Icons.home_outlined, size: 22),
                        label: const Text(
                          "Take me home",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Go back button
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1A53FF),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacementNamed(context, '/');
                        }
                      },
                      icon: const Icon(Icons.arrow_back, size: 20),
                      label: const Text(
                        "Go back",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}
