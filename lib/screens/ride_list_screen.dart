import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:html' as html; 
import '../models/ride_model.dart';
import '../services/auth_service.dart';
import 'onboarding_screen.dart';
import 'create_ride_screen.dart';

class RideListScreen extends StatefulWidget {
  const RideListScreen({super.key});

  @override
  State<RideListScreen> createState() => _RideListScreenState();
}

class _RideListScreenState extends State<RideListScreen> {
  final _authService = AuthService();
  final TextEditingController _profilePhoneController = TextEditingController();
  final TextEditingController _locationSearchController = TextEditingController();
  
  String _locationSearchQuery = '';
  String _locationFilterType = 'Departure'; 

  String _selectedVehicleFilter = 'All'; 
  DateTime? _selectedDateFilter; 
  int _currentTabNavigationIndex = 0; 
  // 🔥 ADDED: This controls how many rides are drawn on the screen initially
  int _currentDisplayLimit = 10;

  @override
  void initState() {
    super.initState();
    // DISABLE 
    //_cleanUpPastRides();   : cleaning up the sweeper bot to reduce read operations on firebase servers.
  }

  @override
  void dispose() {
    _profilePhoneController.dispose();
    _locationSearchController.dispose();
    super.dispose();
  }

  // Regex filter to automatically scrub VIT Registration Numbers from display names
  String _cleanName(String rawName) {
    return rawName.replaceAll(RegExp(r'\b\d{2}[a-zA-Z]{3}\d{4}\b', caseSensitive: false), '').trim();
  }

  Future<void> _cleanUpPastRides() async {
    try {
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();

      final expiredSnap = await FirebaseFirestore.instance
          .collection('rides')
          .where('departureTime', isLessThan: now)
          .get();
      
      for (var doc in expiredSnap.docs) {
        batch.delete(doc.reference);
      }

      final expiredDeclinedRequestsSnap = await FirebaseFirestore.instance
          .collection('requests')
          .where('status', isEqualTo: 'declined')
          .where('departureTime', isLessThan: now)
          .get();

      for (var doc in expiredDeclinedRequestsSnap.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint("ViGo Housekeeper: Cleaned up ${expiredSnap.docs.length} expired rides and ${expiredDeclinedRequestsSnap.docs.length} expired declined requests.");
    } catch (e) {
      debugPrint("ViGo Housekeeper Error: $e");
    }
  }

  void _handleAction(VoidCallback onAuthSuccess) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLogin(onAuthSuccess);
    } else {
      try {
        final isDone = await _authService.isProfileComplete(user.uid);
        if (isDone) {
          onAuthSuccess();
        } else {
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Profile sync error: $e"), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  String _formatDepartureCountdown(DateTime departureTime) {
    final now = DateTime.now();
    final difference = departureTime.difference(now);
    if (difference.isNegative) return "Departed";
    if (difference.inDays >= 1) return "${difference.inDays}d ${difference.inHours % 24}hrs left";
    if (difference.inHours >= 1) return "${difference.inHours}hrs left";
    return "${difference.inMinutes}mins left";
  }

  String _formatDate(DateTime dt) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${dt.day} ${months[dt.month - 1]}";
  }

  String _formatTimeOfDeparture(DateTime dt) {
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return "Posted recently";
    DateTime dt;
    if (timestamp is Timestamp) {
      dt = timestamp.toDate();
    } else if (timestamp is String) {
      dt = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return "Posted recently";
    }

    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return "Posted ${diff.inDays}d ago";
    if (diff.inHours > 0) return "Posted ${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "Posted ${diff.inMinutes}m ago";
    return "Posted just now";
  }

  Future<void> _launchWhatsApp(String ridePhone, String driverId, String hostName, String pickup, String dest) async {
    String finalPhone = ridePhone;
    if (finalPhone.isEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(driverId).get();
        if (userDoc.exists) {
          finalPhone = userDoc.data()?['phone'] ?? '';
        }
      } catch (e) {
        debugPrint("Could not fetch updated phone number: $e");
      }
    }

    if (finalPhone.isEmpty) {
      _showSnackBar("Student has not listed a valid phone number link.");
      return;
    }

    final cleanPhone = finalPhone.replaceAll(RegExp(r'[^\d+]'), '');
    String formattedPhone = cleanPhone;
    if (!formattedPhone.startsWith('+')) {
      formattedPhone = formattedPhone.length == 10 ? "91$formattedPhone" : formattedPhone;
    } else {
      formattedPhone = formattedPhone.replaceAll('?', '');
    }
    
    final templateMessage = Uri.encodeComponent("Hello $hostName, I saw your ViGo Carpool offer from $pickup heading towards $dest. Is there a slot open to split the booking?");
    final url = "https://api.whatsapp.com/send?phone=$formattedPhone&text=$templateMessage";
    
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
    } catch (e) {
      _showSnackBar("Could not open WhatsApp link automatically.");
    }
  }

  Future<void> _directWhatsAppUser(String targetUserId, String defaultName) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(targetUserId).get();
      if (!userDoc.exists || (userDoc.data()?['phone'] ?? '').toString().isEmpty) {
        _showSnackBar("$defaultName hasn't linked a phone number yet.");
        return;
      }

      String phone = userDoc.data()!['phone'];
      phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
      if (!phone.startsWith('+')) {
        phone = phone.length == 10 ? "91$phone" : phone;
      }
      
      final url = "https://api.whatsapp.com/send?phone=$phone&text=Hey $defaultName! Reaching out about our ViGo carpool.";
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
    } catch (e) {
      _showSnackBar("Could not open WhatsApp.");
    }
  }

  Future<void> _sendJoinRequest(String rideId, Ride ride) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.uid == ride.driverId) {
      _showSnackBar("You cannot submit entry requests to join your own ride offer.");
      return;
    }
    try {
      final check = await FirebaseFirestore.instance.collection('requests').where('rideId', isEqualTo: rideId).where('passengerId', isEqualTo: user.uid).get();
      bool hasActiveRequest = check.docs.any((doc) => doc.data()['status'] == 'pending' || doc.data()['status'] == 'accepted');
      if (hasActiveRequest) {
        _showSnackBar("You already have a pending or approved request for this journey.");
        return;
      }
      
      String passengerGender = 'Male';
      try {
         final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
         if (userDoc.exists) {
           passengerGender = userDoc.data()?['gender'] ?? 'Male';
         }
      } catch(e){
         debugPrint("Could not fetch user gender.");
      }

      await FirebaseFirestore.instance.collection('requests').add({
        'rideId': rideId,
        'driverId': ride.driverId, 
        'driverName': ride.driverName, 
        'passengerId': user.uid,
        'passengerName': user.displayName ?? 'VIT Student',
        'passengerEmail': user.email ?? '',
        'passengerGender': passengerGender, 
        'pickupPoint': ride.pickupPoint,
        'destination': ride.destination,
        'departureTime': Timestamp.fromDate(ride.departureTime),
        'status': 'pending', 
        'timestamp': FieldValue.serverTimestamp(),
      });
      _showSnackBar("Join request sent! The host will review your application.");
    } catch (e) {
      _showSnackBar("Transaction error: ${e.toString()}");
    }
  }

  Future<void> _processRequestDecision(String requestId, String rideId, String decisionStatus) async {
    try {
      final requestRef = FirebaseFirestore.instance.collection('requests').doc(requestId);
      final rideRef = FirebaseFirestore.instance.collection('rides').doc(rideId);
      if (decisionStatus == 'accepted') {
        final rideSnap = await rideRef.get();
        if (!rideSnap.exists) { _showSnackBar("Error: Ride not found."); return; }
        final data = rideSnap.data() as Map<String, dynamic>? ?? {};
        var rawSeats = data['availableSeats'] ?? data['totalSeats'] ?? data['seats'];
        int seatsLeft = 0;
        if (rawSeats is num) seatsLeft = rawSeats.toInt();
        else if (rawSeats is String) seatsLeft = int.tryParse(rawSeats) ?? 0;
        if (seatsLeft <= 0) { _showSnackBar("Cannot accept. Vehicle capacity is entirely full."); return; }
        await requestRef.update({'status': 'accepted'});
        await rideRef.update({'availableSeats': seatsLeft - 1});
        _showSnackBar("Student invite accepted. Seats updated.");
      } else {
        await requestRef.update({'status': 'declined'});
        _showSnackBar("Join request declined.");
      }
    } catch (e) {
      _showSnackBar("Network Error: Could not process request.");
    }
  }

  Future<void> _updatePhoneNumber(String newPhone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final cleanPhone = newPhone.trim();
    if (cleanPhone.isEmpty || cleanPhone.length < 10) {
      _showSnackBar("Please specify a valid 10-digit phone number.");
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'phone': cleanPhone,
        'profileComplete': true, 
      }, SetOptions(merge: true));
      _showSnackBar("🛡️ Contact information saved successfully!");
      setState(() {}); 
    } catch (e) {
      _showSnackBar("Database error writing profile metadata: $e");
    }
  }

  Future<void> _confirmClearRequest(String requestId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear from History?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("This will permanently remove this request from your Hub view. This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();
                _showSnackBar("Request removed from your history.");
              } catch (e) {
                _showSnackBar("Failed to clear request: $e");
              }
            },
            child: const Text("Clear Request"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeaveRide(String rideId, String requestId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Leave Ride?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to back out of this carpool? Your confirmed seat will be returned to the host and made available to others."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Stay")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final batch = FirebaseFirestore.instance.batch();
                final requestRef = FirebaseFirestore.instance.collection('requests').doc(requestId);
                final rideRef = FirebaseFirestore.instance.collection('rides').doc(rideId);

                batch.delete(requestRef);

                final rideSnap = await rideRef.get();
                if (rideSnap.exists) {
                  final data = rideSnap.data() as Map<String, dynamic>;
                  var rawSeats = data['availableSeats'] ?? data['totalSeats'] ?? data['seats'];
                  int currentSeats = 0;
                  if (rawSeats is num) currentSeats = rawSeats.toInt();
                  else if (rawSeats is String) currentSeats = int.tryParse(rawSeats) ?? 0;
                  
                  batch.update(rideRef, {'availableSeats': currentSeats + 1});
                }

                await batch.commit();
                _showSnackBar("You have successfully left the ride. Your seat has been released.");
              } catch (e) {
                _showSnackBar("Failed to leave ride: $e");
              }
            },
            child: const Text("Leave Ride"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteRide(String rideId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Ride Offer?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to completely remove this carpool listing from the active feed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Go Back")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('rides').doc(rideId).delete();
                _showSnackBar("Your ride offering has been successfully removed.");
              } catch (e) {
                _showSnackBar("Failed to delete entry: $e");
              }
            },
            child: const Text("Confirm Delete"),
          ),
        ],
      ),
    );
  }

  void _showLogin(VoidCallback onAuthSuccess) {
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Authentication Required", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("Please log in with your verified VIT Google ID to interact with ViGo.", textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                icon: const Icon(Icons.login),
                label: const Text("Sign in with Google"),
                onPressed: () async {
                  try {
                    final loggedInUser = await _authService.signInWithGoogle();
                    if (loggedInUser != null) {
                      final isDone = await _authService.isProfileComplete(loggedInUser.uid);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx); 
                      if (!mounted) return;
                      if (isDone) onAuthSuccess(); 
                      else Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                    }
                  } catch (e) {
                    if (!mounted) return;
                    _showSnackBar("Authentication Failed: $e");
                  }
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _showNotesDialog(String rideId, Map<String, dynamic> rideData, bool isMyOwnRide) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLogin(() {});
      return;
    }

    if (!isMyOwnRide) {
      final checkSnap = await FirebaseFirestore.instance.collection('requests')
          .where('rideId', isEqualTo: rideId)
          .where('passengerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      if (checkSnap.docs.isEmpty) {
        _showSnackBar("🔒 You must be an accepted passenger to read the host's private journey notes.");
        return;
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.speaker_notes, color: Colors.indigo),
            SizedBox(width: 8),
            Text("Journey Notes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          rideData['journeyNotes'] ?? "No additional notes provided.",
          style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Future<void> _handleRideTap(String rideId, Map<String, dynamic> rideData, bool isMyOwnRide, int totalCapacity, int emptySeats) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLogin(() {});
      return;
    }

    if (!isMyOwnRide) {
      final checkSnap = await FirebaseFirestore.instance.collection('requests')
          .where('rideId', isEqualTo: rideId)
          .where('passengerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      if (checkSnap.docs.isEmpty) {
        _showSnackBar("🔒 You must be accepted into this ride to view the passenger manifest.");
        return;
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30))
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("Ride Manifest", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 8),
            Text("${rideData['pickupPoint']} ➔ ${rideData['destination']}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),

            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('requests').where('rideId', isEqualTo: rideId).where('status', isEqualTo: 'accepted').get(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator());
                }

                List<Map<String, dynamic>> occupants = [];
                String hostGender = rideData['driverGender'] ?? rideData['gender'] ?? 'Male'; 
                occupants.add({
                  'userId': rideData['driverId'] ?? rideId, 
                  'name': _cleanName(rideData['driverName'] ?? 'Host'),
                  'role': 'Host', 
                  'gender': hostGender,
                  'color': hostGender.toString().toLowerCase() == 'female' ? Colors.pink[400] : Colors.blue[400],
                });
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final pData = doc.data() as Map<String, dynamic>;
                    String pGender = pData['passengerGender'] ?? 'Male'; 
                    occupants.add({
                      'userId': pData['passengerId'], 
                      'name': _cleanName(pData['passengerName'] ?? 'Passenger'),
                      'role': 'Passenger',
                      'gender': pGender,
                      'color': pGender.toString().toLowerCase() == 'female' ? Colors.pink[400] : Colors.blue[400],
                    });
                  }
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ...occupants.map((occ) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.person, size: 32, color: occ['color']),
                              )),
                          ...List.generate(emptySeats, (index) => const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.person_outline, size: 32, color: Colors.black26),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildOccupantList(occupants),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupantList(List<Map<String, dynamic>> occupants) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: occupants.length,
      itemBuilder: (context, index) {
        final occ = occupants[index];
        final bool isMe = occ['userId'] == currentUserId;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: (occ['color'] as Color).withOpacity(0.1),
            child: Icon(occ['role'] == 'Host' ? Icons.star : Icons.person, color: occ['color'], size: 18),
          ),
          title: Text(isMe ? "${occ['name']} (You)" : occ['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text(occ['role'], style: TextStyle(color: occ['role'] == 'Host' ? Colors.indigo : Colors.grey, fontSize: 12)),
          trailing: isMe ? null : IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.green),
            tooltip: "Message on WhatsApp",
            onPressed: () => _directWhatsAppUser(occ['userId'], occ['name']),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), 
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0, 
        automaticallyImplyLeading: false, 
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: InkWell(
            onTap: () => setState(() => _currentTabNavigationIndex = 0),
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.indigo.withOpacity(0.1),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Image.network(
                "/vigo_full_logo.jpeg", 
                height: 35, 
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        actions: [
          StreamBuilder<User?>(
            stream: _authService.user,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  onPressed: () async {
                    await _authService.signOut();
                    html.window.location.reload(); 
                  },
                );
              }
              return const SizedBox.shrink();
            },
          )
        ],
      ),
      body: _currentTabNavigationIndex == 0 
          ? _buildExplorePoolsFeed() 
          : _currentTabNavigationIndex == 1
              ? _buildMyRidesScreen() 
              : _buildDashboardHub(),
      
      floatingActionButton: _currentTabNavigationIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _handleAction(() { Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRideScreen())); }),
              backgroundColor: Colors.indigo,
              label: const Text("Offer a Ride", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              icon: const Icon(Icons.add, color: Colors.white),
            )
          : null,
          
      bottomNavigationBar: StreamBuilder<User?>(
        stream: _authService.user,
        builder: (context, userSnap) {
          final user = userSnap.data;
          if (user == null) {
            return _buildBottomNavWithBadge(0);
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('requests')
                .where('driverId', isEqualTo: user.uid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, reqSnap) {
              int pendingCount = 0;
              if (reqSnap.hasData) {
                pendingCount = reqSnap.data!.docs.length;
              }
              return _buildBottomNavWithBadge(pendingCount);
            },
          );
        },
      ),
    );
  }

  Widget _buildBottomNavWithBadge(int pendingCount) {
    return BottomNavigationBar(
      currentIndex: _currentTabNavigationIndex,
      selectedItemColor: Colors.indigo,
      unselectedItemColor: Colors.grey,
      onTap: (index) => setState(() => _currentTabNavigationIndex = index),
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.explore_outlined), 
          activeIcon: Icon(Icons.explore), 
          label: "Explore Pools"
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.directions_car_outlined), 
          activeIcon: Icon(Icons.directions_car), 
          label: "My Rides"
        ),
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: pendingCount > 0,
            backgroundColor: Colors.orangeAccent,
            label: Text(pendingCount.toString()),
            child: const Icon(Icons.assignment_outlined),
          ),
          activeIcon: Badge(
            isLabelVisible: pendingCount > 0,
            backgroundColor: Colors.orangeAccent,
            label: Text(pendingCount.toString()),
            child: const Icon(Icons.assignment),
          ),
          label: "My Hub",
        ),
      ],
    );
  }

  Widget _buildLockedScreen(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_person_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () => _handleAction(() => setState(() {})),
              child: const Text("Authenticate Profile"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildExplorePoolsFeed() {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Live Glassmorphic Alert Bar for incoming host requests
        if (currentUser != null)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('requests')
                .where('driverId', isEqualTo: currentUser.uid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, reqSnapshot) {
              if (reqSnapshot.hasData && reqSnapshot.data!.docs.isNotEmpty) {
                final int totalInvites = reqSnapshot.data!.docs.length;

                return InkWell(
                  onTap: () {
                    // Instantly switches tab navigation to 'My Hub'
                    setState(() => _currentTabNavigationIndex = 2);
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.35), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orangeAccent.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.notification_important_rounded, size: 20, color: Colors.orange[800]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Action Required",
                                style: TextStyle(
                                  color: Colors.orange[900],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "You have received $totalInvites ride request${totalInvites > 1 ? 's' : ''}! Tap to review details.",
                                style: TextStyle(
                                  color: Colors.orange[800],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.orange[700]),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink(); 
            },
          ),

        _buildFilterDock(), 
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('rides').snapshots(), 
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Database Connection Issue: ${snapshot.error}"));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              
              final rawRides = snapshot.data?.docs ?? [];
              final now = DateTime.now();

              var rides = rawRides.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                if (data['departureTime'] != null) {
                  final depTime = (data['departureTime'] as Timestamp).toDate();
                  final gracePeriod = now.subtract(const Duration(minutes: 10));
                  if (depTime.isBefore(gracePeriod)) return false; 
                }

                final vType = data['vehicleType'] ?? 'Auto'; 
                bool matchesVehicle = _selectedVehicleFilter == 'All' || vType.toLowerCase() == _selectedVehicleFilter.toLowerCase();
                if (!matchesVehicle) return false;

                if (_selectedDateFilter != null && data['departureTime'] != null) {
                  final depDate = (data['departureTime'] as Timestamp).toDate();
                  bool matchesDate = depDate.year == _selectedDateFilter!.year && depDate.month == _selectedDateFilter!.month && depDate.day == _selectedDateFilter!.day;
                  if (!matchesDate) return false;
                }

                if (_locationSearchQuery.isNotEmpty) {
                  final query = _locationSearchQuery.toLowerCase();
                  if (_locationFilterType == 'Departure') {
                    final pickup = (data['pickupPoint'] ?? '').toString().toLowerCase();
                    if (!pickup.contains(query)) return false;
                  } else {
                    final destination = (data['destination'] ?? '').toString().toLowerCase();
                    if (!destination.contains(query)) return false;
                  }
                }

                return true;
              }).toList();

              // ALWAYS SORTS BY MOST RECENTLY CREATED FIRST
              rides.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                
                final Timestamp? aTime = aData['timestamp'] as Timestamp? ?? aData['createdAt'] as Timestamp? ?? aData['departureTime'] as Timestamp?;
                final Timestamp? bTime = bData['timestamp'] as Timestamp? ?? bData['createdAt'] as Timestamp? ?? bData['departureTime'] as Timestamp?;
                
                if (aTime == null || bTime == null) return 0;
                return bTime.compareTo(aTime); 
              });

              // 🔥 1. Save the total number of matches BEFORE we chop the list
              int totalMatches = rides.length;

              // 🔥 2. Chop the list based on the dynamic limit
              if (rides.length > _currentDisplayLimit) {
                rides = rides.sublist(0, _currentDisplayLimit);
              }

              if (rides.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                // 🔥 3. Add +2 to make room for BOTH the Top Banner and Bottom Footer
                itemCount: rides.length + 2, 
                itemBuilder: (context, index) {
                  
                  // 🔥 4. TOP BANNER (Index 0)
                  if (index == 0) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.indigo[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.indigo[700]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Showing active pools. Use filters above to explore specific journeys!",
                              style: TextStyle(color: Colors.indigo[900], fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // 🔥 5. BOTTOM FOOTER (Rendered at the very last index)
                  if (index == rides.length + 1) {
                    if (totalMatches > _currentDisplayLimit) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _currentDisplayLimit += 5; // Adds 5 more rides to the UI
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.indigo,
                              side: BorderSide(color: Colors.indigo.withOpacity(0.3)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text("Show more rides", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    } else {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.flag_circle_outlined, color: Colors.grey[400], size: 32),
                              const SizedBox(height: 8),
                              Text(
                                "You've reached the end of the road!",
                                style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }

                  // 🔥 6. NORMAL RIDE CARDS (Offset by -1 to account for the top banner)
                  final doc = rides[index - 1];
                  final ride = Ride.fromFirestore(doc);
                  final data = doc.data() as Map<String, dynamic>;
                  final String vehicle = data['vehicleType'] ?? 'Auto';
                  final String phone = data['driverPhone'] ?? '';
                  
                  return _buildPremiumRideCard(ride, vehicle, phone, doc.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDock() {
    final filterOptions = [
      {'label': 'All Pools', 'icon': Icons.all_inclusive},
      {'label': 'Auto', 'icon': Icons.electric_rickshaw},
      {'label': 'Cab', 'icon': Icons.local_taxi}
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _locationSearchController,
                    onChanged: (val) => setState(() => _locationSearchQuery = val),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: _locationFilterType == 'Departure' ? "Search pickup point..." : "Search drop point...",
                      hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.indigo),
                      suffixIcon: _locationSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.black54),
                              onPressed: () {
                                _locationSearchController.clear();
                                setState(() => _locationSearchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.withOpacity(0.1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _locationFilterType,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.indigo, size: 24),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 'Departure', child: Text("By Pickup")),
                      DropdownMenuItem(value: 'Destination', child: Text("By Drop")),
                    ],
                    onChanged: (val) => setState(() => _locationFilterType = val!),
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...filterOptions.map((opt) {
                        final isSelected = _selectedVehicleFilter == opt['label']!.toString().split(' ')[0];
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            height: 38,
                            child: FilterChip(
                              showCheckmark: false,
                              avatar: Icon(
                                opt['icon'] as IconData, 
                                size: 14, 
                                color: isSelected ? Colors.white : Colors.indigo
                              ),
                              label: Text(opt['label'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              selected: isSelected,
                              selectedColor: Colors.indigo,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87, 
                              ),
                              backgroundColor: const Color(0xFFF1F3F5),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12), 
                                side: BorderSide.none
                              ),
                              onSelected: (_) => setState(() => _selectedVehicleFilter = opt['label']!.toString().split(' ')[0]),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 2),
                      if (_selectedDateFilter != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: SizedBox(
                            height: 38,
                            child: InputChip(
                              label: Text(_formatDate(_selectedDateFilter!), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), 
                              selected: true, 
                              selectedColor: Colors.teal,
                              labelStyle: const TextStyle(color: Colors.white),
                              onDeleted: () => setState(() => _selectedDateFilter = null),
                              deleteIconColor: Colors.white, 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none),
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.calendar_month_rounded, color: Colors.teal, size: 20), 
                            tooltip: "Select departure date filter",
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context, 
                                initialDate: DateTime.now(), 
                                firstDate: DateTime.now().subtract(const Duration(days: 1)), 
                                lastDate: DateTime.now().add(const Duration(days: 60)),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Colors.indigo,
                                        onPrimary: Colors.white,
                                        onSurface: Colors.black87,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                }
                              );
                              if (picked != null) setState(() => _selectedDateFilter = picked);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyRidesScreen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildLockedScreen("My Rides Locked", "Please log in to view your upcoming confirmed itineraries and active hosting duties.");
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.indigo,
              tabs: [
                Tab(icon: Icon(Icons.star_outline), text: "Hosting"),
                Tab(icon: Icon(Icons.airline_seat_recline_normal), text: "Joined"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildActiveHostingSubView(user.uid),
                _buildActiveJoinedSubView(user.uid),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActiveHostingSubView(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('rides').where('driverId', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs.toList();
        
        // Safe Timestamp extraction
        docs.sort((a, b) {
          final aMap = a.data() as Map<String, dynamic>;
          final bMap = b.data() as Map<String, dynamic>;
          final aTime = aMap['departureTime'] as Timestamp?;
          final bTime = bMap['departureTime'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return aTime.compareTo(bTime);
        });

        if (docs.isEmpty) return _buildMiniEmptyState(Icons.drive_eta, "Not hosting any rides", "When you offer a ride, it will appear here for easy access.");

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final ride = Ride.fromFirestore(doc);
            final data = doc.data() as Map<String, dynamic>;
            final String vehicle = data['vehicleType'] ?? 'Auto';
            final String phone = data['driverPhone'] ?? '';
            return _buildPremiumRideCard(ride, vehicle, phone, doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildActiveJoinedSubView(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('passengerId', isEqualTo: uid).where('status', isEqualTo: 'accepted').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final reqDocs = snapshot.data!.docs;
        
        if (reqDocs.isEmpty) return _buildMiniEmptyState(Icons.airline_seat_recline_normal, "No confirmed rides yet", "When a host accepts your join request, the confirmed ride will appear here.");

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqDocs.length,
          itemBuilder: (context, index) {
            final reqData = reqDocs[index].data() as Map<String, dynamic>;
            final String rideId = reqData['rideId'];

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('rides').doc(rideId).get(),
              builder: (ctx, rideSnap) {
                if (rideSnap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                if (!rideSnap.hasData || !rideSnap.data!.exists) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red[100]!)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.redAccent), SizedBox(width: 8), Text("Ride Cancelled", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16))]),
                        const SizedBox(height: 8),
                        Text("The host (${reqData['driverName']}) has deleted this route.", style: const TextStyle(color: Colors.black87)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: () => FirebaseFirestore.instance.collection('requests').doc(reqDocs[index].id).delete(), style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent), child: const Text("Clear Warning"))
                      ],
                    ),
                  );
                }

                final rideDoc = rideSnap.data!;
                final ride = Ride.fromFirestore(rideDoc);
                final data = rideDoc.data() as Map<String, dynamic>;
                final String vehicle = data['vehicleType'] ?? 'Auto';
                final String phone = data['driverPhone'] ?? '';
                
                return _buildPremiumRideCard(ride, vehicle, phone, rideDoc.id, data);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardHub() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildLockedScreen("Hub Locked", "Please log in to manage incoming ride requests and track your pooling approvals.");
    }

    return Column(
      children: [
        _buildProfileSettingsCard(user.uid), 
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: const TabBar(
                    labelColor: Colors.indigo,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.indigo,
                    tabs: [
                      Tab(icon: Icon(Icons.arrow_downward), text: "Incoming Invites"),
                      Tab(icon: Icon(Icons.arrow_upward), text: "My Sent Requests"),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildIncomingInvitesSubView(user.uid),
                      _buildSentRequestsSubView(user.uid),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Profile Card WITH Gender Identity editing and Batch Write capabilities
  Widget _buildProfileSettingsCard(String uid) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        String existingPhone = "";
        String existingGender = "Male"; 
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          existingPhone = data?['phone'] ?? "";
          existingGender = data?['gender'] ?? "Male";
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_circle_outlined, color: Colors.indigo, size: 22),
                      SizedBox(width: 8),
                      Text("Account Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  if (existingPhone.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12)),
                      child: const Text("LINKED ✓", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12)),
                      child: const Text("MISSING INFO", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
              const SizedBox(height: 8),
              Text(
                existingPhone.isNotEmpty 
                    ? "Your current linked primary contact number is +91 $existingPhone. You can modify it at any time below."
                    : "You haven't added a phone number yet. Please provide a verified number to allow co-passengers to launch WhatsApp group connections.",
                style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              
              // Phone Input Row
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 45,
                      child: TextField(
                        controller: _profilePhoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: existingPhone.isNotEmpty ? existingPhone : "Enter 10-digit number",
                          prefixText: "+91 ",
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 45,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        _updatePhoneNumber(_profilePhoneController.text);
                        _profilePhoneController.clear();
                        FocusScope.of(context).unfocus(); 
                      },
                      child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              
              // Gender Selection Box
              const SizedBox(height: 20),
              const Text("Gender Identity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              Container(
                height: 45,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: ['Male', 'Female', 'Other'].contains(existingGender) ? existingGender : 'Male',
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.indigo),
                    items: ['Male', 'Female', 'Other'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (newValue) async {
                      if (newValue != null && newValue != existingGender) {
                        try {
                          final batch = FirebaseFirestore.instance.batch();
                          
                          // 1. Update the main user profile
                          final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
                          batch.set(userRef, {'gender': newValue}, SetOptions(merge: true));

                          // 2. Update all active rides hosted by this user
                          final ridesSnap = await FirebaseFirestore.instance.collection('rides').where('driverId', isEqualTo: uid).get();
                          for (var doc in ridesSnap.docs) {
                            batch.update(doc.reference, {'driverGender': newValue});
                          }

                          // 3. Update all active requests made by this user
                          final reqSnap = await FirebaseFirestore.instance.collection('requests').where('passengerId', isEqualTo: uid).get();
                          for (var doc in reqSnap.docs) {
                            batch.update(doc.reference, {'passengerGender': newValue});
                          }

                          await batch.commit();

                          _showSnackBar("Gender synchronized successfully!");
                          setState(() {});
                        } catch (e) {
                          _showSnackBar("Failed to sync gender: $e");
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIncomingInvitesSubView(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('driverId', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final reqDocs = snapshot.data!.docs.toList();
        reqDocs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); 
        });

        if (reqDocs.isEmpty) return _buildMiniEmptyState(Icons.mail_outline, "No incoming invites", "When other students ask to join your carpool paths, they will emerge here.");

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqDocs.length,
          itemBuilder: (context, index) {
            final doc = reqDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String status = data['status'] ?? 'pending';
            final String rideId = data['rideId'] ?? '';

            final Timestamp? departureTimestamp = data['departureTime'];
            final bool isExpired = departureTimestamp != null && departureTimestamp.toDate().isBefore(DateTime.now());

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('rides').doc(rideId).snapshots(),
              builder: (ctx, rideSnap) {
                
                if (!rideSnap.hasData) return const SizedBox.shrink();

                if (!rideSnap.data!.exists) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50], 
                      borderRadius: BorderRadius.circular(16), 
                      border: Border.all(color: Colors.red[100]!)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              // 🔥 Mask applied here
                              child: Text(
                                _cleanName(data['passengerName'] ?? 'VIT Student'), 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87), 
                                overflow: TextOverflow.ellipsis
                              )
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(12)),
                              child: const Text("RIDE DELETED", style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey), 
                              onPressed: () => _confirmClearRequest(doc.id), 
                              tooltip: "Clear orphaned invite"
                            )
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "You cancelled the route: ${data['pickupPoint']} ➔ ${data['destination']}", 
                          style: const TextStyle(fontSize: 13, color: Colors.grey)
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 🔥 Mask applied here
                              Expanded(child: Text(_cleanName(data['passengerName'] ?? 'VIT Student'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                              _buildStatusChip(isExpired && status == 'pending' ? 'expired' : status),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey), onPressed: () => _confirmClearRequest(doc.id), tooltip: "Clear from history")
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text("Route: ${data['pickupPoint']} ➔ ${data['destination']}", style: const TextStyle(fontSize: 13, color: Colors.black54)),
                          ),
                          children: [
                            if (status == 'pending' && !isExpired) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)), onPressed: () => _processRequestDecision(doc.id, rideId, 'declined'), child: const Text("Decline"))),
                                  const SizedBox(width: 12),
                                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white), onPressed: () => _processRequestDecision(doc.id, rideId, 'accepted'), child: const Text("Accept Request"))),
                                ],
                              )
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSentRequestsSubView(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('passengerId', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final reqDocs = snapshot.data!.docs.toList();
        reqDocs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); 
        });

        if (reqDocs.isEmpty) return _buildMiniEmptyState(Icons.near_me_outlined, "No requests sent yet", "Tap 'Join Ride' on an active pool offer card to register an application route link.");

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqDocs.length,
          itemBuilder: (context, index) {
            final doc = reqDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String status = data['status'] ?? 'pending';
            final String rideId = data['rideId'] ?? '';

            final Timestamp? departureTimestamp = data['departureTime'];
            final bool isExpired = departureTimestamp != null && departureTimestamp.toDate().isBefore(DateTime.now());

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('rides').doc(rideId).snapshots(),
              builder: (ctx, rideSnap) {
                
                if (!rideSnap.hasData) return const SizedBox.shrink();

                if (!rideSnap.data!.exists) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50], 
                      borderRadius: BorderRadius.circular(16), 
                      border: Border.all(color: Colors.red[100]!)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 🔥 Mask applied here
                            Expanded(child: Text("Pool with ${_cleanName(data['driverName'] ?? 'Host')}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(12)),
                              child: const Text("CANCELLED BY HOST", style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey), onPressed: () => _confirmClearRequest(doc.id), tooltip: "Clear cancelled request")
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text("Journey: ${data['pickupPoint']} ➔ ${data['destination']}", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 🔥 Mask applied here
                          Expanded(child: Text("Pool with ${_cleanName(data['driverName'] ?? 'Host')}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis)),
                          _buildStatusChip(isExpired && status == 'pending' ? 'expired' : status),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey), onPressed: () => _confirmClearRequest(doc.id), tooltip: "Cancel or clear request")
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text("Journey: ${data['pickupPoint']} ➔ ${data['destination']}", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg = Colors.amber[50]!;
    Color fg = Colors.amber[800]!;
    String label = status.toUpperCase();
    if (status == 'accepted') { bg = Colors.green[50]!; fg = Colors.green[800]!; } 
    else if (status == 'declined') { bg = Colors.grey[100]!; fg = Colors.grey[600]!; }
    else if (status == 'expired') { bg = Colors.red[50]!; fg = Colors.red[800]!; label = "RIDE DEPARTED"; } 
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildMiniEmptyState(IconData icon, String title, String sub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.indigo[100]),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumRideCard(Ride ride, String vehicle, String phone, String docId, Map<String, dynamic> rawData) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isMyOwnRide = currentUser != null && ride.driverId == currentUser.uid;
    
    // 🔥 Mask applied here
    String hostName = _cleanName(ride.driverName); 

    // --- HOST GENDER LOGIC ---
    //String hostGender = (rawData['driverGender'] ?? rawData['gender'] ?? 'Male').toString().toLowerCase();
    //Color bookmarkColor = hostGender == 'female' ? Colors.pink[400]! : Colors.blue[400]!;
   // String genderTooltip = hostGender == 'female' ? "Hosted by Female" : "Hosted by Male";
    
    String journeyNotes = rawData['journeyNotes'] ?? '';
    bool hasNotes = journeyNotes.trim().isNotEmpty;

    final rawTotal = rawData['totalSeats'] ?? rawData['seats'] ?? ride.availableSeats;
    int totalCapacity = rawTotal is num ? rawTotal.toInt() : (int.tryParse(rawTotal.toString()) ?? 4);
    final rawAvailable = rawData['availableSeats'] ?? rawData['availableseats'] ?? totalCapacity;
    int currentAvailable = rawAvailable is num ? rawAvailable.toInt() : (int.tryParse(rawAvailable.toString()) ?? totalCapacity);
    int acceptedPassengers = totalCapacity - currentAvailable;
    if (acceptedPassengers < 0) acceptedPassengers = 0;
    
    int joinedCount = acceptedPassengers + 1;
    int emptySeats = currentAvailable < 0 ? 0 : currentAvailable;
    return InkWell(
      onTap: () => _handleRideTap(docId, rawData, isMyOwnRide, totalCapacity, emptySeats),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.indigo[50],
                    child: Text(hostName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hostName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Row(
                          children: [
                            const Text("Verified VIT Student", style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w500)),
                            const Text(" • ", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            Text(_getTimeAgo(rawData['timestamp'] ?? rawData['createdAt']), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(vehicle.toLowerCase() == 'cab' ? Icons.local_taxi : Icons.electric_rickshaw, size: 14, color: Colors.amber[800]),
                        const SizedBox(width: 4),
                        Text(vehicle, style: TextStyle(color: Colors.amber[800], fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  // REMOVING GENDER BOOKMARKS - FOR HOST
                  // --- GENDER BOOKMARK ---
                  //const SizedBox(width: 8),
                  //Tooltip(
                    //message: genderTooltip,
                    //child: Icon(Icons.bookmark, color: bookmarkColor, size: 22),
                  //),

                  if (hasNotes) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showNotesDialog(docId, rawData, isMyOwnRide),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                        child: const Icon(Icons.speaker_notes, size: 14, color: Colors.blue),
                      ),
                    ),
                  ],

                  if (isMyOwnRide) ...[
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22), tooltip: "Cancel this offer", onPressed: () => _confirmDeleteRide(docId))
                  ]
                ],
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Color(0xFFF1F3F5))),
              
              Row(
                children: [
                  Column(
                    children: [
                      const Icon(Icons.radio_button_checked, size: 18, color: Colors.indigo),
                      Container(width: 2, height: 24, color: Colors.grey[200]),
                      const Icon(Icons.location_on, size: 18, color: Colors.redAccent),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ride.pickupPoint, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                        const SizedBox(height: 18),
                        Text(ride.destination, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                  ),
                  
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.group, size: 14, color: Colors.indigo),
                          const SizedBox(width: 4),
                          Text("$joinedCount joined", style: const TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      currentAvailable <= 0 
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cancel, size: 14, color: Colors.redAccent),
                              SizedBox(width: 4),
                              Text("Ride Full, Cannot join", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 13)),
                            ],
                          )
                        : Text("$currentAvailable spots left", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(_formatDepartureCountdown(ride.departureTime), style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text("${_formatDate(ride.departureTime)}, ${_formatTimeOfDeparture(ride.departureTime)}", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (currentUser == null) {
                          _showLogin(() { 
                            _launchWhatsApp(phone, ride.driverId, hostName, ride.pickupPoint, ride.destination);
                          });
                        } else {
                          _launchWhatsApp(phone, ride.driverId, hostName, ride.pickupPoint, ride.destination);
                        }
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text("Chat"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo, 
                        side: BorderSide(color: Colors.indigo[100]!), 
                        padding: const EdgeInsets.all(12), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  Expanded(
                    child: currentUser == null 
                    ? ElevatedButton(
                        onPressed: () => _showLogin(() => _sendJoinRequest(docId, ride)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text("Join Ride", style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    : isMyOwnRide 
                      ? ElevatedButton(
                          onPressed: null, 
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.grey[600], elevation: 0, padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Text("Your Ride", style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('requests').where('rideId', isEqualTo: docId).where('passengerId', isEqualTo: currentUser.uid).snapshots(),
                          builder: (ctx, snap) {
                            String btnText = "Join Ride";
                            Color btnColor = Colors.indigo;
                            VoidCallback? onPressedAction = () => _sendJoinRequest(docId, ride);

                            if (snap.hasData && snap.data!.docs.isNotEmpty) {
                              final reqDoc = snap.data!.docs.first;
                              final reqData = reqDoc.data() as Map<String, dynamic>;
                              final status = reqData['status'] ?? 'pending';
                              
                              if (status == 'accepted') { 
                                btnText = "Leave Ride"; 
                                btnColor = Colors.redAccent; 
                                onPressedAction = () => _confirmLeaveRide(docId, reqDoc.id); 
                              } 
                              else if (status == 'pending') { 
                                btnText = "Cancel Request"; 
                                btnColor = Colors.orange; 
                                onPressedAction = () => _confirmClearRequest(reqDoc.id); 
                              }
                            } else {
                              if (currentAvailable <= 0) { 
                                btnText = "Pool Full"; 
                                btnColor = Colors.redAccent; 
                                onPressedAction = null; 
                              }
                            }
                            
                            return ElevatedButton(
                              onPressed: onPressedAction,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: btnColor, disabledBackgroundColor: btnColor.withOpacity(0.8), disabledForegroundColor: Colors.white, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(btnText, style: const TextStyle(fontWeight: FontWeight.bold)),
                            );
                          },
                      ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 40, right: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.indigo[50], shape: BoxShape.circle), child: Icon(Icons.directions_car_filled_outlined, size: 80, color: Colors.indigo[300])),
            const SizedBox(height: 24),
            Text("No matching pools found", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Adjust your filters or be the first to publish a ride for this date range!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}