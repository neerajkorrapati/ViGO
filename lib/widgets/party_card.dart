import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../models/party_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class PartyCard extends StatefulWidget {
  final PartyModel party;
  const PartyCard({super.key, required this.party});

  @override
  State<PartyCard> createState() => _PartyCardState();
}

class _PartyCardState extends State<PartyCard> {
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();
  late Timer _timer;
  Duration _timeLeft = Duration.zero;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _calculateTime();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _calculateTime());
  }

  void _calculateTime() {
    if (mounted) setState(() => _timeLeft = widget.party.departureTime.difference(DateTime.now()));
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  Future<void> _handleJoin() async {
    final String? uid = _auth.currentUserId;
    
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please log out and in again."))
      );
      return;
    }

    bool alreadyJoined = widget.party.passengers.any((p) => p['id'] == uid);
    if (alreadyJoined) {
      _openWhatsApp();
      return;
    }

    setState(() => _isJoining = true);

    try {
      UserModel? userProfile = await _auth.getUserProfile(uid);
      if (userProfile == null) throw Exception("Complete your profile in the menu first.");

      await _firestore.joinParty(widget.party.id, {
        'id': userProfile.id,
        'name': userProfile.name,
        'phoneNumber': userProfile.phoneNumber,
        'gender': userProfile.gender,
      });

      _openWhatsApp();
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _openWhatsApp() async {
    if (widget.party.passengers.isEmpty) return;
    
    // The host is the first person in the passengers array
    final hostPhone = widget.party.passengers[0]['phoneNumber'];
    final url = "https://wa.me/$hostPhone?text=Hi! Joining your ride to ${widget.party.destination}";
    final Uri uri = Uri.parse(url);

    try {
      // mode: LaunchMode.externalApplication is vital for Web and Mobile compatibility
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open WhatsApp. Check your browser settings."))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = _auth.currentUserId ?? '';
    final bool isHost = widget.party.hostId == currentUserId;
    final bool isPassenger = widget.party.passengers.any((p) => p['id'] == currentUserId);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.party.destination, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                Text("${_timeLeft.inHours}h ${_timeLeft.inMinutes % 60}m left", 
                  style: const TextStyle(color: Color(0xFF1A53FF), fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(widget.party.totalSeats, (i) {
                    if (i < widget.party.passengers.length) {
                      return Icon(Icons.person, 
                        color: widget.party.passengers[i]['gender'] == 'F' ? Colors.pink : const Color(0xFF1A53FF));
                    }
                    return const Icon(Icons.person_outline, color: Colors.grey);
                  }),
                ),
                Row(
                  children: [
                    if (isHost) IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red), 
                      onPressed: () => _firestore.deleteParty(widget.party.id)
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (widget.party.isFull && !isPassenger) || _isJoining ? null : _handleJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPassenger ? Colors.green : const Color(0xFF1A53FF),
                        foregroundColor: Colors.white,
                      ),
                      child: _isJoining 
                        ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isPassenger ? "CHAT" : (widget.party.isFull ? "FULL" : "JOIN")),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}