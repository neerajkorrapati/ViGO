import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../models/party_model.dart';

class PartyCard extends StatefulWidget {
  final PartyModel party;
  const PartyCard({super.key, required this.party});

  @override
  State<PartyCard> createState() => _PartyCardState();
}

class _PartyCardState extends State<PartyCard> {
  late Timer _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculateTime();
    // Update the countdown every minute for performance
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _calculateTime());
  }

  void _calculateTime() {
    if (mounted) {
      setState(() {
        _timeLeft = widget.party.departureTime.difference(DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isUrgent = _timeLeft.inMinutes < 15;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isUrgent ? Colors.red.shade100 : Colors.transparent),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isUrgent ? Colors.red.shade50 : const Color(0xFFF0F4FF),
                  child: Icon(
                    widget.party.vehicleType == 'auto' ? Icons.electric_rickshaw : Icons.local_taxi,
                    color: isUrgent ? Colors.red : const Color(0xFF1A53FF),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.party.destination, 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("Pickup: ${widget.party.pickup}", 
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(isUrgent ? "LEAVING SOON" : "DEPARTS IN",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isUrgent ? Colors.red : Colors.grey)),
                    Text("${_timeLeft.inHours}h ${_timeLeft.inMinutes % 60}m",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isUrgent ? Colors.red : Colors.black)),
                  ],
                )
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Visual Seat Tracker
                Row(
                  children: List.generate(widget.party.totalSeats, (index) {
                    return Icon(
                      Icons.person,
                      size: 20,
                      color: index < widget.party.filledSeats ? const Color(0xFF1A53FF) : Colors.grey.shade200,
                    );
                  }),
                ),
                ElevatedButton(
                  onPressed: widget.party.isFull ? null : () async {
                    HapticFeedback.lightImpact();
                    final url = "https://wa.me/${widget.party.phoneNumber}?text=Hey ${widget.party.hostName}, joining your ViGo ride to ${widget.party.destination}!";
                    await launchUrl(Uri.parse(url));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A53FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(widget.party.isFull ? "FULL" : "JOIN RIDE"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}