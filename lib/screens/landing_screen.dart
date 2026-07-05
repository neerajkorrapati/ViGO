import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ride_list_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _statsKey = GlobalKey();

  int _activeRidesCount = 20; // Fallback
  int _registeredUsersCount = 150; // Fallback
  bool _statsAnimated = false;

  @override
  void initState() {
    super.initState();
    _fetchDbCounts();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollListener();
    });
  }

  Future<void> _fetchDbCounts() async {
    try {
      final docSnap = await FirebaseFirestore.instance.collection('stats').doc('global').get();
      if (mounted) {
        if (docSnap.exists) {
          final data = docSnap.data();
          if (data != null) {
            setState(() {
              _activeRidesCount = data['activeRidesCount'] ?? 24;
              _registeredUsersCount = data['usersCount'] ?? 150;
            });
            debugPrint("Landing stats loaded successfully from Firestore: Rides=$_activeRidesCount, Users=$_registeredUsersCount");
          }
        } else {
          debugPrint("Firestore stats note: Document 'stats/global' does not exist in your database. Please create it with 'activeRidesCount' and 'usersCount' fields.");
        }
      }
    } catch (e) {
      // Permission-denied or other Firebase errors are caught gracefully here.
      // Fallback numbers (24 and 150) are preserved so they still animate up smoothly.
      debugPrint("Firebase connection note: using local stats fallback. Error detail: $e");
    }
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final context = _statsKey.currentContext;
    if (context != null && !_statsAnimated) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        final double screenHeight = MediaQuery.of(context).size.height;
        
        // Trigger animation when the top of the stats section enters the bottom 85% of viewport
        if (position.dy < screenHeight * 0.85) {
          setState(() {
            _statsAnimated = true;
          });
        }
      }
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollToStats() {
    final context = _statsKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "$title is coming soon!",
          style: GoogleFonts.instrumentSans(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        width: 280,
        backgroundColor: const Color(0xFF0B0A5C),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 800;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double appBarHeight = AppBar().preferredSize.height;
    final double heroHeight = screenHeight - appBarHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Image.network(
            "/vigo_full_logo.jpeg",
            height: isDesktop ? 50 : 35,
            fit: BoxFit.contain,
          ),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            // Full Screen Hero Section
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: heroHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 120.0 : 24.0,
                    vertical: isDesktop ? 60.0 : 20.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Your Campus,\nConnected.",
                              style: TextStyle(
                                fontSize: isDesktop ? 64 : 42,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                                letterSpacing: -2,
                              ),
                              textAlign: isDesktop ? TextAlign.start : TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              "Stop overpaying for cabs. Match with VITians, split the fare, and travel smart...",
                              style: TextStyle(
                                fontSize: isDesktop ? 20 : 16,
                                color: Colors.black.withValues(alpha: 0.6),
                                height: 1.6,
                              ),
                              textAlign: isDesktop ? TextAlign.start : TextAlign.center,
                            ),
                            const SizedBox(height: 48),
                            ElevatedButton(
                              onPressed: () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const RideListScreen()),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[800],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Explore Rides →",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isDesktop) const SizedBox(width: 80),
                      if (isDesktop)
                        Expanded(
                          child: Center(
                            child: Image.network("/vigo_full_logo.jpeg", fit: BoxFit.contain),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 60),

            // Animated Stats Section (Ticket Stub design)
            Container(
              key: _statsKey,
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 120.0 : 24.0,
                vertical: 40,
              ),
              child: Column(
                children: [
                  Text(
                    "ViGO by the Numbers",
                    style: GoogleFonts.instrumentSans(
                      fontSize: isDesktop ? 32 : 26,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Making campus commutes affordable, social, and sustainable.",
                    style: GoogleFonts.instrumentSans(
                      fontSize: isDesktop ? 16 : 14,
                      color: const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (isDesktop)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildHoverCard(
                          child: StatTicketCard(
                            icon: Icons.directions_car_rounded,
                            line1: "Active Rides",
                            line2: "On Platform",
                            counterWidget: AnimatedCounter(
                              targetValue: _activeRidesCount,
                              play: _statsAnimated,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        _buildHoverCard(
                          child: StatTicketCard(
                            icon: Icons.people_alt_rounded,
                            line1: "Registered",
                            line2: "Users",
                            counterWidget: AnimatedCounter(
                              targetValue: _registeredUsersCount,
                              play: _statsAnimated,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        _buildHoverCard(
                          child: StatTicketCard(
                            icon: Icons.co2_rounded,
                            line1: "CO2 Emissions",
                            line2: "Saved",
                            counterWidget: AnimatedCounter(
                              targetValue: (_activeRidesCount * 4.2).round(),
                              suffix: " kg",
                              play: _statsAnimated,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildHoverCard(
                          child: StatTicketCard(
                            icon: Icons.directions_car_rounded,
                            line1: "Active Rides",
                            line2: "On Platform",
                            counterWidget: AnimatedCounter(
                              targetValue: _activeRidesCount,
                              play: _statsAnimated,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildHoverCard(
                          child: StatTicketCard(
                            icon: Icons.people_alt_rounded,
                            line1: "Registered",
                            line2: "Users",
                            counterWidget: AnimatedCounter(
                              targetValue: _registeredUsersCount,
                              play: _statsAnimated,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildHoverCard(
                          child: StatTicketCard(
                            icon: Icons.co2_rounded,
                            line1: "CO2 Emissions",
                            line2: "Saved",
                            counterWidget: AnimatedCounter(
                              targetValue: (_activeRidesCount * 4.2).round(),
                              suffix: " kg",
                              play: _statsAnimated,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 80),

            // Premium Image-Based Footer
            _buildResponsiveFooter(context, isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildHoverCard({required Widget child}) {
    return _HoverStatCard(child: child);
  }

  Widget _buildResponsiveFooter(BuildContext context, bool isDesktop) {
    if (isDesktop) {
      return AspectRatio(
        aspectRatio: 889 / 568,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double w = constraints.maxWidth;
            final double h = constraints.maxHeight;

            return Stack(
              children: [
                // Render the user's template footer image exactly as the background, covering the container edge-to-edge
                Positioned.fill(
                  child: Image.asset(
                    'web/assets/landing_footer_bg.png',
                    fit: BoxFit.fill,
                  ),
                ),

                // Fade white mask on the top edge of the footer image to blend it with white section above
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: h * 0.08, // Reduced fade height to only cover the top edge (8%)
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Brand Column: Ride Now Button positioned below the pre-rendered slogan
                Positioned(
                  left: w * 0.110,
                  top: h * 0.86,
                  child: OutlinedButton(
                    onPressed: _scrollToTop,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFACC15), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: w * 0.022 > 18 ? w * 0.022 : 18,
                        vertical: h * 0.022 > 11 ? h * 0.022 : 11,
                      ),
                    ),
                    child: Text(
                      "Ride Now",
                      style: GoogleFonts.instrumentSans(
                        fontSize: w * 0.015 > 12 ? w * 0.015 : 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                // Column 2: Site Page Links positioned to match exactly with the top point of the first blue vertical line
                Positioned(
                  left: w * 0.525,
                  top: h * 0.72,
                  width: w * 0.20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFooterLink("HOME", fontSize: w * 0.016 > 12 ? w * 0.016 : 12, onTap: _scrollToTop),
                      SizedBox(height: h * 0.02),
                      _buildFooterLink("CLIENT WORK", fontSize: w * 0.016 > 12 ? w * 0.016 : 12, onTap: () => _showComingSoon(context, "Client Work")),
                      SizedBox(height: h * 0.02),
                      _buildFooterLink("OUR PRODUCTS", fontSize: w * 0.016 > 12 ? w * 0.016 : 12, onTap: () => _showComingSoon(context, "Our Products")),
                      SizedBox(height: h * 0.02),
                      _buildFooterLink("ABOUT", fontSize: w * 0.016 > 12 ? w * 0.016 : 12, onTap: _scrollToStats),
                    ],
                  ),
                ),

                // Column 3: Social Media Links positioned to match exactly with the top point of the second blue vertical line
                Positioned(
                  left: w * 0.775,
                  top: h * 0.72,
                  width: w * 0.20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HoverSocialIcon(
                        icon: Icons.camera_alt_outlined,
                        label: "Instagram",
                        size: w * 0.025 > 18 ? w * 0.025 : 18,
                        fontSize: w * 0.015 > 12 ? w * 0.015 : 12,
                        onTap: () => _showComingSoon(context, "Instagram"),
                      ),
                      SizedBox(height: h * 0.025),
                      HoverSocialIcon(
                        customIcon: TwitterXIcon(color: Colors.white, size: w * 0.022 > 16 ? w * 0.022 : 16),
                        label: "X",
                        size: w * 0.025 > 18 ? w * 0.025 : 18,
                        fontSize: w * 0.015 > 12 ? w * 0.015 : 12,
                        onTap: () => _showComingSoon(context, "Twitter"),
                      ),
                      SizedBox(height: h * 0.025),
                      HoverSocialIcon(
                        icon: Icons.link_outlined,
                        label: "Linkedin",
                        size: w * 0.025 > 18 ? w * 0.025 : 18,
                        fontSize: w * 0.015 > 12 ? w * 0.015 : 12,
                        onTap: () => _showComingSoon(context, "Linkedin"),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      // Mobile Footer Layout
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            // Top Section (Renders the background image in its full aspect ratio)
            AspectRatio(
              aspectRatio: 889 / 568,
              child: Image.asset(
                'web/assets/landing_footer_bg.png',
                fit: BoxFit.fill,
              ),
            ),

            // Bottom Section (Solid dark blue container with navigation links and button)
            Container(
              color: const Color(0xFF0B0A5C),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _scrollToTop,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFACC15), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    child: Text(
                      "Ride Now",
                      style: GoogleFonts.instrumentSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),
                  // Mobile links
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _buildFooterLink("HOME", fontSize: 14, onTap: _scrollToTop),
                      _buildFooterLink("CLIENT WORK", fontSize: 14, onTap: () => _showComingSoon(context, "Client Work")),
                      _buildFooterLink("OUR PRODUCTS", fontSize: 14, onTap: () => _showComingSoon(context, "Our Products")),
                      _buildFooterLink("ABOUT", fontSize: 14, onTap: _scrollToStats),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),
                  // Mobile social icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HoverSocialIcon(
                        icon: Icons.camera_alt_outlined,
                        label: "",
                        onTap: () => _showComingSoon(context, "Instagram"),
                      ),
                      const SizedBox(width: 24),
                      HoverSocialIcon(
                        customIcon: const TwitterXIcon(color: Colors.white, size: 22),
                        label: "",
                        onTap: () => _showComingSoon(context, "Twitter"),
                      ),
                      const SizedBox(width: 24),
                      HoverSocialIcon(
                        icon: Icons.sports_basketball_outlined,
                        label: "",
                        onTap: () => _showComingSoon(context, "Dribbble"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildFooterLink(String text, {required double fontSize, required VoidCallback onTap}) {
    return _HoverLinkText(text: text, fontSize: fontSize, onTap: onTap);
  }
}

// -----------------------------------------------------------------
// BRAND TICKET DESIGN WIDGETS
// -----------------------------------------------------------------

class StatTicketCard extends StatelessWidget {
  final Widget counterWidget;
  final String line1;
  final String line2;
  final IconData icon;

  const StatTicketCard({
    super.key,
    required this.counterWidget,
    required this.line1,
    required this.line2,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ScallopedBottomClipper(),
      child: Container(
        width: 220,
        height: 340,
        decoration: BoxDecoration(
          color: const Color(0xFF6B93E9), // Ticket bottom medium-blue color
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Column(
          children: [
            // Top segment (Very light blue background with car/people/co2 icons)
            Container(
              height: 100,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFE8EEFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 48,
                  color: const Color(0xFF6B93E9),
                ),
              ),
            ),
            
            // Bottom segment contents (Animated counters, label pills, barcode)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dynamic numbers
                    counterWidget,
                    
                    // Horizontal white line divider
                    Container(
                      width: 80,
                      height: 1.2,
                      color: Colors.white54,
                    ),
                    
                    // Translucent pills holding labels
                    Column(
                      children: [
                        _buildLabelPill(line1),
                        const SizedBox(height: 6),
                        _buildLabelPill(line2),
                        const SizedBox(height: 6),
                        _buildLabelPill(""), // Pre-rendered empty bottom pill matching design
                      ],
                    ),
                    
                    // Stylized barcode block
                    Container(
                      height: 48,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(24, (index) {
                          final double barWidth = (index % 3 == 0) ? 3.0 : ((index % 2 == 0) ? 1.0 : 2.0);
                          return Container(
                            width: barWidth,
                            color: const Color(0xFF6B93E9),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelPill(String text) {
    return Container(
      height: 20,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Text(
              text.toUpperCase(),
              style: GoogleFonts.instrumentSans(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
    );
  }
}

class ScallopedBottomClipper extends CustomClipper<Path> {
  final double waveWidth;
  final double waveHeight;

  ScallopedBottomClipper({this.waveWidth = 13.8, this.waveHeight = 6.0});

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - waveHeight);

    double x = 0;
    while (x < size.width) {
      path.quadraticBezierTo(
        x + waveWidth / 2,
        size.height,
        x + waveWidth,
        size.height - waveHeight,
      );
      x += waveWidth;
    }

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// -----------------------------------------------------------------
// CUSTOM HOVER & ANIMATION UTILITIES
// -----------------------------------------------------------------

class _HoverStatCard extends StatefulWidget {
  final Widget child;

  const _HoverStatCard({required this.child});

  @override
  State<_HoverStatCard> createState() => _HoverStatCardState();
}

class _HoverStatCardState extends State<_HoverStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _isHovered ? -8 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.16 : 0.08),
              blurRadius: _isHovered ? 20 : 10,
              offset: Offset(0, _isHovered ? 10 : 5),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

class _HoverLinkText extends StatefulWidget {
  final String text;
  final double fontSize;
  final VoidCallback onTap;

  const _HoverLinkText({required this.text, required this.fontSize, required this.onTap});

  @override
  State<_HoverLinkText> createState() => _HoverLinkTextState();
}

class _HoverLinkTextState extends State<_HoverLinkText> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          style: GoogleFonts.instrumentSans(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
            color: _isHovered ? const Color(0xFFFACC15) : Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class HoverSocialIcon extends StatefulWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final double size;
  final double fontSize;
  final VoidCallback onTap;

  const HoverSocialIcon({
    super.key,
    this.icon,
    this.customIcon,
    required this.label,
    this.size = 24,
    this.fontSize = 14,
    required this.onTap,
  });

  @override
  State<HoverSocialIcon> createState() => _HoverSocialIconState();
}

class _HoverSocialIconState extends State<HoverSocialIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.customIcon != null)
              TwitterXIcon(color: _isHovered ? const Color(0xFFFACC15) : Colors.white, size: widget.size - 2)
            else
              Icon(
                widget.icon,
                color: _isHovered ? const Color(0xFFFACC15) : Colors.white,
                size: widget.size,
              ),
            if (widget.label.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: GoogleFonts.instrumentSans(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.bold,
                  color: _isHovered ? const Color(0xFFFACC15) : Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TwitterXIcon extends StatelessWidget {
  final Color color;
  final double size;

  const TwitterXIcon({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TwitterXPainter(color: color),
      ),
    );
  }
}

class _TwitterXPainter extends CustomPainter {
  final Color color;

  _TwitterXPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(const Offset(4, 4), Offset(size.width - 4, size.height - 4), paint);
    canvas.drawLine(Offset(size.width - 4, 4), Offset(4, size.height - 4), paint);
  }

  @override
  bool shouldRepaint(covariant _TwitterXPainter oldDelegate) => oldDelegate.color != color;
}

// Animated stats counter widget
class AnimatedCounter extends StatefulWidget {
  final int targetValue;
  final String suffix;
  final bool play;
  final double fontSize;

  const AnimatedCounter({
    super.key,
    required this.targetValue,
    this.suffix = '',
    required this.play,
    this.fontSize = 44,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _animation = IntTween(begin: 0, end: widget.targetValue).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );
    if (widget.play) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
      _controller.forward();
    } else if (oldWidget.targetValue != widget.targetValue) {
      _animation = IntTween(begin: _animation.value, end: widget.targetValue).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
      );
      if (widget.play) {
        _controller.reset();
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          "${_animation.value}${widget.suffix}",
          style: GoogleFonts.outfit(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.0,
          ),
        );
      },
    );
  }
}