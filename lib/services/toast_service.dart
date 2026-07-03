import 'dart:async';
import 'package:flutter/material.dart';

class ToastService {
  static OverlayEntry? _currentOverlay;
  static Timer? _dismissTimer;

  static void show(BuildContext context, String message, {bool isWarning = false}) {
    _dismissTimer?.cancel();
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
    }

    final translatedMsg = _translateError(message);
    final isReallyWarning = isWarning || 
        message.toLowerCase().contains('error') || 
        message.toLowerCase().contains('failed') || 
        message.toLowerCase().contains('closed') ||
        message.toLowerCase().contains('expired') ||
        message.toLowerCase().contains('must be') ||
        message.toLowerCase().contains('cannot');

    final overlayState = Overlay.of(context);
    
    // We create the overlay entry with the animated toast widget.
    final entry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: translatedMsg,
        isWarning: isReallyWarning,
        onDismiss: () {
          _dismissTimer?.cancel();
          if (_currentOverlay != null) {
            _currentOverlay!.remove();
            _currentOverlay = null;
          }
        },
      ),
    );

    _currentOverlay = entry;
    overlayState.insert(entry);

    // Timeout loop of exactly 10 seconds
    _dismissTimer = Timer(const Duration(seconds: 10), () {
      if (_currentOverlay == entry) {
        _currentOverlay!.remove();
        _currentOverlay = null;
      }
    });
  }

  static String _translateError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('popup_closed') || 
        lower.contains('popup-closed') || 
        lower.contains('closed by user') ||
        lower.contains('popup_closed_by_user')) {
      return "Sign-In window closed before completion. Please try again.";
    }
    if (lower.contains('use your @vitstudent.ac.in email')) {
      return "Access restricted. Please use your institutional @vitstudent.ac.in email address.";
    }
    if (lower.contains('network-request-failed') || lower.contains('network error') || lower.contains('connectivity')) {
      return "Network connectivity issue. Please check your internet connection and try again.";
    }
    if (lower.contains('invalid-credential') || lower.contains('invalid credential')) {
      return "Authentication credentials invalid. Please try signing in again.";
    }
    if (lower.contains('channel-error') || lower.contains('channel error')) {
      return "Communication error with authentication server. Please try again.";
    }
    if (lower.contains('session expired')) {
      return "Session expired. Please log out and sign in again.";
    }
    if (lower.contains('student has not listed a valid phone number')) {
      return "The student has not linked a valid phone number.";
    }
    if (lower.contains('could not open whatsapp')) {
      return "Could not open WhatsApp. Please check your browser or device settings.";
    }
    
    // Fallback or cleaned message
    return error
        .replaceAll('Exception:', '')
        .replaceAll('FirebaseException:', '')
        .trim();
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isWarning;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.isWarning,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );

    // Spring-like entry transition (Curves.easeOutBack)
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    // Warm amber warning tint: #F5B041, dark text: #4A2700
    // General info tint: const Color(0xFF1E88E5), dark text: Colors.white
    final bgColor = widget.isWarning ? const Color(0xFFF5B041) : const Color(0xFFE8F0FE);
    final textColor = widget.isWarning ? const Color(0xFF5D3E00) : const Color(0xFF1A53FF);
    final iconColor = widget.isWarning ? const Color(0xFF7E5109) : const Color(0xFF1A53FF);
    final icon = widget.isWarning ? Icons.warning_amber_rounded : Icons.info_outline;

    return Positioned(
      top: 24,
      right: 24,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: SlideTransition(
            position: _offsetAnimation,
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isWarning ? const Color(0xFFE59828) : const Color(0xFFD0E1FD),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: iconColor, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.isWarning ? "Warning" : "Notice",
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.message,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _dismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Icon(Icons.close, color: iconColor.withValues(alpha: 0.6), size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
