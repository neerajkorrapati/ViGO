import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:web/web.dart' as web; 
import 'package:flutter_svg/flutter_svg.dart';
import '../models/ride_model.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import 'package:google_fonts/google_fonts.dart';
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

  @override
  void initState() {
    super.initState();
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
          ToastService.show(context, "Profile sync error: $e", isWarning: true);
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
        final data = rideSnap.data() ?? {};
        var rawSeats = data['availableSeats'] ?? data['totalSeats'] ?? data['seats'];
        int seatsLeft = 0;
        if (rawSeats is num) {
          seatsLeft = rawSeats.toInt();
        } else if (rawSeats is String) {
          seatsLeft = int.tryParse(rawSeats) ?? 0;
        }
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
                  if (rawSeats is num) {
                    currentSeats = rawSeats.toInt();
                  } else if (rawSeats is String) {
                    currentSeats = int.tryParse(rawSeats) ?? 0;
                  }
                  
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
                      if (isDone) {
                        onAuthSuccess();
                      } else {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                      }
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
    final bool isDesktop = MediaQuery.of(context).size.width > 800;
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
                height: 50, 
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
                    web.window.location.reload(); 
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
      
      floatingActionButton: (_currentTabNavigationIndex == 0 && !isDesktop)
          ? FloatingActionButton(
              onPressed: () => _handleAction(() { Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRideScreen())); }),
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.add, color: Colors.white),
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
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    Widget buildMainList() {
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('rides').limit(15).snapshots(), // changing limit to 15 users from 30, to reduce server read operations load.
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Database Connection Issue: ${snapshot.error}"));
          if (snapshot.connectionState == ConnectionState.waiting) return _buildFullScreenLoader();
          
          final rawRides = snapshot.data?.docs ?? [];
          final now = DateTime.now();

          var rides = rawRides.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            
            if (data['departureTime'] != null) {
              final depTime = (data['departureTime'] as Timestamp).toDate();
              if (depTime.isBefore(now)) return false; 
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

          // 🔥 ALWAYS SORTS BY MOST RECENTLY CREATED FIRST (Regardless of filters)
          rides.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            
            // Uses the document creation time, safely falls back if missing
            final Timestamp? aTime = aData['timestamp'] as Timestamp? ?? aData['createdAt'] as Timestamp? ?? aData['departureTime'] as Timestamp?;
            final Timestamp? bTime = bData['timestamp'] as Timestamp? ?? bData['createdAt'] as Timestamp? ?? bData['departureTime'] as Timestamp?;
            
            if (aTime == null || bTime == null) return 0;
            
            // b.compareTo(a) reverses the order so the newest is at the top
            return bTime.compareTo(aTime); 
          });

          // 🔥 Truncate AFTER sorting to ensure you get the absolute 15 newest rides
          if (rides.length > 15) {
            rides = rides.sublist(0, 15);
          }

          if (rides.isEmpty) return _buildEmptyState();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            itemBuilder: (context, index) {
              final doc = rides[index];
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

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: buildMainList()),
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey[200]!)),
            ),
            child: _buildDesktopFilterSidebar(),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterDock(), 
          Expanded(
            child: buildMainList(),
          ),
        ],
      );
    }
  }

  Widget _buildVehicleModeSelector() {
    final modes = [
      {'label': 'Auto', 'icon': Icons.electric_rickshaw, 'index': 0},
      {'label': 'All Pools', 'icon': Icons.all_inclusive, 'index': 1},
      {'label': 'Cab', 'icon': Icons.local_taxi, 'index': 2},
    ];

    int activeIndex = 1; // Default 'All'
    if (_selectedVehicleFilter == 'Auto') activeIndex = 0;
    if (_selectedVehicleFilter == 'Cab') activeIndex = 2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE9E8FA),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9E8FA), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: modes.map((mode) {
              final label = mode['label'] as String;
              final icon = mode['icon'] as IconData;
              final idx = mode['index'] as int;
              final isSelected = activeIndex == idx;

              return InkWell(
                onTap: () {
                  setState(() {
                    if (idx == 0) _selectedVehicleFilter = 'Auto';
                    if (idx == 1) _selectedVehicleFilter = 'All';
                    if (idx == 2) _selectedVehicleFilter = 'Cab';
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 80,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 56,
                        child: Center(
                          child: isSelected
                              ? Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 26,
                                    color: const Color(0xFF2E4ECF),
                                  ),
                                )
                              : Icon(
                                  icon,
                                  size: 26,
                                  color: const Color(0xFF2E4ECF),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E4ECF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.instrumentSans(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Text(
                          label,
                          style: GoogleFonts.instrumentSans(
                            color: const Color(0xFF7E8CA0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Dot indicators below
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final isSelected = activeIndex == i;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isSelected ? 16 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2E4ECF) : const Color(0xFFD2D6DC),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartureDateSelector() {
    final hasDate = _selectedDateFilter != null;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context, 
          initialDate: _selectedDateFilter ?? DateTime.now(), 
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA), // light green bg
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Color(0xFF137333), // dark green color
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Select date",
                    style: GoogleFonts.instrumentSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasDate ? _formatDate(_selectedDateFilter!) : "Any date",
                    style: GoogleFonts.instrumentSans(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (hasDate)
              IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() => _selectedDateFilter = null);
                },
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferRideButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E4ECF), // blue color from image
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () => _handleAction(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateRideScreen()),
          );
        }),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                size: 14,
                color: Color(0xFF2E4ECF), // blue icon color
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Offer a Ride",
              style: GoogleFonts.instrumentSans(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopFilterSidebar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Filters",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                TextButton(
                  onPressed: () {
                    _locationSearchController.clear();
                    setState(() {
                      _locationSearchQuery = '';
                      _selectedVehicleFilter = 'All';
                      _selectedDateFilter = null;
                    });
                  },
                  child: const Text("Reset", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F3F5)),
            
            // Search section
            const Text(
              "Search Route",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.indigo[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _locationFilterType,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.indigo),
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'Departure', child: Text("By Pickup Point")),
                    DropdownMenuItem(value: 'Destination', child: Text("By Destination")),
                  ],
                  onChanged: (val) => setState(() => _locationFilterType = val!),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _locationSearchController,
                onChanged: (val) => setState(() => _locationSearchQuery = val),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: _locationFilterType == 'Departure' ? "Search pickup point..." : "Search drop point...",
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.indigo),
                  suffixIcon: _locationSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.black54),
                          onPressed: () {
                            _locationSearchController.clear();
                            setState(() => _locationSearchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(height: 24),
  
            // Vehicle selection
            const Text(
              "Vehicle Mode",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            _buildVehicleModeSelector(),
            const SizedBox(height: 24),
  
            // Date selection
            const Text(
              "Departure Date",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            _buildDepartureDateSelector(),
            const SizedBox(height: 24),
  
            // Offer a Ride button
            _buildOfferRideButton(),
          ],
        ),
      ),
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
        if (!snapshot.hasData) return _buildFullScreenLoader();
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
        if (!snapshot.hasData) return _buildFullScreenLoader();
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
        if (!snapshot.hasData) return _buildFullScreenLoader();
        
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
        if (!snapshot.hasData) return _buildFullScreenLoader();
        
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

  Widget _buildFullScreenLoader() {
    return SizedBox.expand(
      child: Image.network(
        'assets/loadScreen.gif',
        fit: BoxFit.cover,
        alignment: Alignment.center,
      ),
    );
  }

  Widget _buildPremiumRideCard(Ride ride, String vehicle, String phone, String docId, Map<String, dynamic> rawData) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(ride.driverId).get(),
      builder: (context, userSnap) {
        String profilePicUrl = '';
        if (userSnap.hasData && userSnap.data!.exists) {
          final userData = userSnap.data!.data() as Map<String, dynamic>?;
          profilePicUrl = userData?['profilePic'] ?? '';
        }
        return _buildPremiumRideCardWithData(ride, vehicle, phone, docId, rawData, profilePicUrl);
      },
    );
  }

  Widget _buildPremiumRideCardWithData(
    Ride ride,
    String vehicle,
    String phone,
    String docId,
    Map<String, dynamic> rawData,
    String profilePicUrl,
  ) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isMyOwnRide = currentUser != null && ride.driverId == currentUser.uid;
    String hostName = _cleanName(ride.driverName);
    
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

    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      return _buildDesktopCard(
        ride: ride,
        vehicle: vehicle,
        phone: phone,
        docId: docId,
        rawData: rawData,
        profilePicUrl: profilePicUrl,
        currentUser: currentUser,
        isMyOwnRide: isMyOwnRide,
        hostName: hostName,
        hasNotes: hasNotes,
        joinedCount: joinedCount,
        currentAvailable: currentAvailable,
        totalCapacity: totalCapacity,
        emptySeats: emptySeats,
      );
    } else {
      return _buildMobileCard(
        ride: ride,
        vehicle: vehicle,
        phone: phone,
        docId: docId,
        rawData: rawData,
        profilePicUrl: profilePicUrl,
        currentUser: currentUser,
        isMyOwnRide: isMyOwnRide,
        hostName: hostName,
        hasNotes: hasNotes,
        joinedCount: joinedCount,
        currentAvailable: currentAvailable,
        totalCapacity: totalCapacity,
        emptySeats: emptySeats,
      );
    }
  }

  Widget _buildDesktopCard({
    required Ride ride,
    required String vehicle,
    required String phone,
    required String docId,
    required Map<String, dynamic> rawData,
    required String profilePicUrl,
    required User? currentUser,
    required bool isMyOwnRide,
    required String hostName,
    required bool hasNotes,
    required int joinedCount,
    required int currentAvailable,
    required int totalCapacity,
    required int emptySeats,
  }) {
    final pickupCity = _getCityName(ride.pickupPoint);
    final pickupAbbr = _getAbbreviation(ride.pickupPoint);
    final destCity = _getCityName(ride.destination);
    final destAbbr = _getAbbreviation(ride.destination);
    final travelDuration = _getTravelDuration(ride.pickupPoint, ride.destination);
    final arrivalTime = _getArrivalTime(ride.departureTime, travelDuration);

    final departureTimeStr = "${_formatDate(ride.departureTime)}, ${_formatTimeOfDeparture(ride.departureTime)}";
    final arrivalTimeStr = "${_formatDate(arrivalTime)}, ${_formatTimeOfDeparture(arrivalTime)}";

    return InkWell(
      onTap: () => _handleRideTap(docId, rawData, isMyOwnRide, totalCapacity, emptySeats),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Left main section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top: Pill tag, Host name, Subtitle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildVehicleBadge(vehicle),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              hostName,
                              style: GoogleFonts.inriaSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            if (hasNotes) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _showNotesDialog(docId, rawData, isMyOwnRide),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                                  child: const Icon(Icons.speaker_notes, size: 10, color: Colors.blue),
                                ),
                              ),
                            ],
                            if (isMyOwnRide) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _confirmDeleteRide(docId),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                                  child: const Icon(Icons.delete_outline, size: 11, color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: "Verified VIT Student",
                                style: GoogleFonts.inriaSans(
                                  color: Colors.green[600],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: " • ${_getTimeAgo(rawData['timestamp'] ?? rawData['createdAt'])}",
                                style: GoogleFonts.inriaSans(
                                  color: Colors.grey[500],
                                  fontSize: 10,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Bottom: Car, Source details, Trajectory, Destination details
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildCarAvatarWidget(profilePicUrl, hostName, 92, isDesktop: true),
                        const SizedBox(width: 24),
                        _buildLocationDetailColumn(pickupCity, pickupAbbr, departureTimeStr, crossAxisAlignment: CrossAxisAlignment.start),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildRouteTrajectoryWidget(vehicle, travelDuration),
                        ),
                        const SizedBox(width: 12),
                        _buildLocationDetailColumn(destCity, destAbbr, arrivalTimeStr, crossAxisAlignment: CrossAxisAlignment.end),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Vertical Divider
            Container(
              width: 1,
              color: Colors.grey[200],
            ),
            // Right ticket stub section
            Container(
              width: 180,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.group_rounded, size: 14, color: Colors.indigo[800]),
                      const SizedBox(width: 5),
                      Text(
                        "$joinedCount joined",
                        style: GoogleFonts.instrumentSans(
                          color: Colors.indigo[800],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentAvailable <= 0 ? "Full" : "$currentAvailable spots left",
                    style: GoogleFonts.instrumentSans(
                      color: currentAvailable <= 0 ? Colors.red : Colors.green[700],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDepartureCountdown(ride.departureTime),
                    style: GoogleFonts.instrumentSans(
                      color: Colors.orange[800],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Chat button
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (currentUser == null) {
                          _showLogin(() => _launchWhatsApp(phone, ride.driverId, hostName, ride.pickupPoint, ride.destination));
                        } else {
                          _launchWhatsApp(phone, ride.driverId, hostName, ride.pickupPoint, ride.destination);
                        }
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 13),
                      label: const Text("Chat", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo,
                        side: BorderSide(color: Colors.indigo[100]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Join Ride button
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: _buildResponsiveJoinButton(
                      currentUser: currentUser,
                      isMyOwnRide: isMyOwnRide,
                      docId: docId,
                      ride: ride,
                      currentAvailable: currentAvailable,
                      height: 34,
                      borderRadius: 8,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),),
    );
  }

  Widget _buildMobileCard({
    required Ride ride,
    required String vehicle,
    required String phone,
    required String docId,
    required Map<String, dynamic> rawData,
    required String profilePicUrl,
    required User? currentUser,
    required bool isMyOwnRide,
    required String hostName,
    required bool hasNotes,
    required int joinedCount,
    required int currentAvailable,
    required int totalCapacity,
    required int emptySeats,
  }) {
    final pickupCity = _getCityName(ride.pickupPoint);
    final pickupAbbr = _getAbbreviation(ride.pickupPoint);
    final destCity = _getCityName(ride.destination);
    final destAbbr = _getAbbreviation(ride.destination);
    final travelDuration = _getTravelDuration(ride.pickupPoint, ride.destination);
    final arrivalTime = _getArrivalTime(ride.departureTime, travelDuration);

    final departureTimeStr = "${_formatDate(ride.departureTime)}, ${_formatTimeOfDeparture(ride.departureTime)}";
    final arrivalTimeStr = "${_formatDate(arrivalTime)}, ${_formatTimeOfDeparture(arrivalTime)}";

    return InkWell(
      onTap: () => _handleRideTap(docId, rawData, isMyOwnRide, totalCapacity, emptySeats),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: TicketCard(
          cutPosition: 52.0,
          cutRadius: 8.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section (above notches, height 52)
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFFE8EAF6),
                      child: Text(
                        hostName.isNotEmpty ? hostName.substring(0, 1).toUpperCase() : 'U',
                        style: GoogleFonts.inriaSans(
                          color: const Color(0xFF3F51B5),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hostName,
                      style: GoogleFonts.inriaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                    if (hasNotes) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _showNotesDialog(docId, rawData, isMyOwnRide),
                        child: const Icon(Icons.speaker_notes, size: 12, color: Colors.blue),
                      ),
                    ],
                    if (isMyOwnRide) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _confirmDeleteRide(docId),
                        child: const Icon(Icons.delete_outline, size: 13, color: Colors.redAccent),
                      ),
                    ],
                    const Spacer(),
                    _buildVehicleBadge(vehicle),
                  ],
                ),
              ),
              
              // Body Section (below notches)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Route Detail Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildLocationDetailColumn(pickupCity, pickupAbbr, departureTimeStr, crossAxisAlignment: CrossAxisAlignment.start),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildRouteTrajectoryWidget(vehicle, travelDuration),
                        ),
                        const SizedBox(width: 8),
                        _buildLocationDetailColumn(destCity, destAbbr, arrivalTimeStr, crossAxisAlignment: CrossAxisAlignment.end),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Metadata Row: Joined, spots, countdown
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.group_rounded, size: 14, color: Colors.indigo[800]),
                            const SizedBox(width: 4),
                            Text(
                              "$joinedCount joined",
                              style: GoogleFonts.instrumentSans(
                                color: Colors.indigo[800],
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          currentAvailable <= 0 ? "Full" : "$currentAvailable spots left",
                          style: GoogleFonts.instrumentSans(
                            color: currentAvailable <= 0 ? Colors.red : Colors.green[700],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatDepartureCountdown(ride.departureTime),
                          style: GoogleFonts.instrumentSans(
                            color: Colors.orange[800],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Buttons Row (side-by-side)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (currentUser == null) {
                                  _showLogin(() => _launchWhatsApp(phone, ride.driverId, hostName, ride.pickupPoint, ride.destination));
                                } else {
                                  _launchWhatsApp(phone, ride.driverId, hostName, ride.pickupPoint, ride.destination);
                                }
                              },
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 12),
                              label: const Text("Chat", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo,
                                side: BorderSide(color: Colors.indigo[100]!),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: _buildResponsiveJoinButton(
                              currentUser: currentUser,
                              isMyOwnRide: isMyOwnRide,
                              docId: docId,
                              ride: ride,
                              currentAvailable: currentAvailable,
                              height: 34,
                              borderRadius: 8,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationDetailColumn(String city, String abbreviation, String dateTime, {required CrossAxisAlignment crossAxisAlignment}) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          city,
          style: GoogleFonts.instrumentSans(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          abbreviation,
          style: GoogleFonts.instrumentSans(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          dateTime,
          style: GoogleFonts.instrumentSans(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildRouteTrajectoryWidget(String vehicle, String duration) {
    final isCab = vehicle.toLowerCase() == 'cab';
    final travelIcon = isCab ? Icons.local_taxi : Icons.electric_rickshaw;
    final iconColor = isCab ? Colors.blue[800]! : Colors.amber[800]!;

    return SizedBox(
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DashedArcPainter(color: Colors.grey[300]!),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 2,
            child: Icon(
              travelIcon,
              size: 15,
              color: iconColor,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Text(
              duration,
              textAlign: TextAlign.center,
              style: GoogleFonts.instrumentSans(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarAvatarWidget(String profilePic, String hostName, double carWidth, {bool isDesktop = false}) {
    final double carHeight = carWidth * (210 / 297);
    return SizedBox(
      width: carWidth,
      height: carHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'web/assets/cabConvertible.svg',
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: carWidth * 0.40 + 9.0,
            top: isDesktop ? carHeight * 0.02 : carHeight * 0.18,
            width: carWidth * 0.25,
            height: carWidth * 0.25,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 3,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: ClipOval(
                child: profilePic.isNotEmpty
                    ? Image.network(
                        profilePic,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, _, __) => _buildInitialsAvatar(hostName),
                      )
                    : _buildInitialsAvatar(hostName),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(String name) {
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';
    return Container(
      color: const Color(0xFFE8EAF6),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.inriaSans(
          color: const Color(0xFF3F51B5),
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildVehicleBadge(String vehicle) {
    final isCab = vehicle.toLowerCase() == 'cab';
    final label = isCab ? "CAB" : "AUTO";
    final icon = isCab ? Icons.local_taxi : Icons.electric_rickshaw;
    final bgColor = isCab ? const Color(0xFFE3F2FD) : const Color(0xFFFFF3E0);
    final borderColor = isCab ? const Color(0xFF90CAF9) : const Color(0xFFFFB74D);
    final contentColor = isCab ? const Color(0xFF0D47A1) : const Color(0xFFE65100);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: contentColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.instrumentSans(
              color: contentColor,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _getAbbreviation(String location) {
    final clean = location.trim().toLowerCase();
    if (clean.contains('katpadi') || clean.contains('kpd')) return 'KPD';
    if (clean.contains('vit') || clean.contains('vellore')) return 'VIT';
    if (clean.contains('chennai') || clean.contains('maa') || clean.contains('airport')) {
      if (clean.contains('chennai') || clean.contains('maa')) return 'MAA';
      if (clean.contains('bangalore') || clean.contains('bengaluru') || clean.contains('blr')) return 'BLR';
      return 'APT';
    }
    if (clean.contains('bangalore') || clean.contains('bengaluru') || clean.contains('blr')) return 'BLR';
    if (clean.contains('hostel')) return 'HST';
    if (clean.contains('main gate') || clean.contains('maingate')) return 'MGT';
    if (clean.contains('chittoor')) return 'CTR';
    
    final words = location.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      String abb = '';
      for (var w in words) {
        if (w.isNotEmpty) abb += w[0];
      }
      if (abb.length >= 2) return abb.toUpperCase();
    }
    if (location.length >= 3) {
      return location.substring(0, 3).toUpperCase();
    }
    return location.toUpperCase();
  }

  String _getTravelDuration(String from, String to) {
    final f = from.trim().toLowerCase();
    final t = to.trim().toLowerCase();
    
    bool fromLocal = f.contains('katpadi') || f.contains('kpd') || f.contains('vit') || f.contains('vellore') || f.contains('hostel') || f.contains('gate');
    bool toLocal = t.contains('katpadi') || t.contains('kpd') || t.contains('vit') || t.contains('vellore') || t.contains('hostel') || t.contains('gate');
    
    if (fromLocal && toLocal) {
      return "25m";
    }
    if (f.contains('chennai') || f.contains('maa') || t.contains('chennai') || t.contains('maa')) {
      return "3h 30m";
    }
    if (f.contains('bangalore') || f.contains('blr') || t.contains('bangalore') || t.contains('blr') || f.contains('bengaluru') || t.contains('bengaluru')) {
      return "4h 0m";
    }
    return "45m";
  }

  DateTime _getArrivalTime(DateTime departureTime, String duration) {
    if (duration.contains('h')) {
      final parts = duration.split(' ');
      int hours = 0;
      int minutes = 0;
      for (var p in parts) {
        if (p.endsWith('h')) {
          hours = int.tryParse(p.replaceAll('h', '')) ?? 0;
        } else if (p.endsWith('m')) {
          minutes = int.tryParse(p.replaceAll('m', '')) ?? 0;
        }
      }
      return departureTime.add(Duration(hours: hours, minutes: minutes));
    } else {
      int minutes = int.tryParse(duration.replaceAll('m', '')) ?? 30;
      return departureTime.add(Duration(minutes: minutes));
    }
  }

  String _getCityName(String location) {
    final clean = location.trim().toLowerCase();
    if (clean.contains('katpadi') || clean.contains('kpd')) return 'Katpadi';
    if (clean.contains('vit') || clean.contains('vellore')) return 'Vellore';
    if (clean.contains('chennai') || clean.contains('maa')) {
      if (clean.contains('airport')) return 'Chennai Airport';
      return 'Chennai';
    }
    if (clean.contains('bangalore') || clean.contains('blr') || clean.contains('bengaluru')) {
      if (clean.contains('airport')) return 'Bangalore Airport';
      return 'Bangalore';
    }
    if (clean.contains('hostel')) return 'Hostels';
    if (clean.contains('main gate') || clean.contains('maingate')) return 'Main Gate';
    
    final words = location.trim().split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      return words.map((w) {
        if (w.isEmpty) return '';
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      }).join(' ');
    }
    return location;
  }

  Widget _buildResponsiveJoinButton({
    required User? currentUser,
    required bool isMyOwnRide,
    required String docId,
    required Ride ride,
    required int currentAvailable,
    required double height,
    required double borderRadius,
    required double fontSize,
  }) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: Colors.indigo,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
    );

    if (currentUser == null) {
      return ElevatedButton(
        onPressed: () => _showLogin(() => _sendJoinRequest(docId, ride)),
        style: style,
        child: Text("Join", style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
      );
    }

    if (isMyOwnRide) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[200],
          foregroundColor: Colors.grey[600],
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        ),
        child: Text("Your Ride", style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('rideId', isEqualTo: docId)
          .where('passengerId', isEqualTo: currentUser.uid)
          .snapshots(),
      builder: (ctx, snap) {
        String btnText = "Join";
        Color btnColor = Colors.indigo;
        VoidCallback? onPressedAction = () => _sendJoinRequest(docId, ride);

        if (snap.hasData && snap.data!.docs.isNotEmpty) {
          final reqDoc = snap.data!.docs.first;
          final reqData = reqDoc.data() as Map<String, dynamic>;
          final status = reqData['status'] ?? 'pending';

          if (status == 'accepted') {
            btnText = "Leave";
            btnColor = Colors.redAccent;
            onPressedAction = () => _confirmLeaveRide(docId, reqDoc.id);
          } else if (status == 'pending') {
            btnText = "Cancel";
            btnColor = Colors.orange;
            onPressedAction = () => _confirmClearRequest(reqDoc.id);
          }
        } else {
          if (currentAvailable <= 0) {
            btnText = "Full";
            btnColor = Colors.redAccent;
            onPressedAction = null;
          }
        }

        return ElevatedButton(
          onPressed: onPressedAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: btnColor,
            disabledBackgroundColor: btnColor.withOpacity(0.8),
            disabledForegroundColor: Colors.white,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
          ),
          child: Text(btnText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
        );
      },
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
    ToastService.show(context, msg);
  }
}

// -------------------------------------------------------------
// TICKET DESIGN UTILITIES & CUSTOM PAINTERS
// -------------------------------------------------------------

class TicketCard extends StatelessWidget {
  final Widget child;
  final double cutPosition;
  final double cutRadius;

  const TicketCard({
    super.key,
    required this.child,
    required this.cutPosition,
    this.cutRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TicketCardPainter(cutPosition: cutPosition, cutRadius: cutRadius),
      child: ClipPath(
        clipper: TicketClipper(cutPosition: cutPosition, cutRadius: cutRadius),
        child: child,
      ),
    );
  }
}

class TicketClipper extends CustomClipper<Path> {
  final double cutPosition;
  final double cutRadius;

  TicketClipper({required this.cutPosition, this.cutRadius = 8.0});

  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    
    // Right side notch
    path.lineTo(size.width, cutPosition - cutRadius);
    path.arcToPoint(
      Offset(size.width, cutPosition + cutRadius),
      radius: Radius.circular(cutRadius),
      clockwise: false,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    
    // Left side notch
    path.lineTo(0, cutPosition + cutRadius);
    path.arcToPoint(
      Offset(0, cutPosition - cutRadius),
      radius: Radius.circular(cutRadius),
      clockwise: false,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

class TicketCardPainter extends CustomPainter {
  final double cutPosition;
  final double cutRadius;

  TicketCardPainter({required this.cutPosition, required this.cutRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    
    // Right side notch
    path.lineTo(size.width, cutPosition - cutRadius);
    path.arcToPoint(
      Offset(size.width, cutPosition + cutRadius),
      radius: Radius.circular(cutRadius),
      clockwise: false,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    
    // Left side notch
    path.lineTo(0, cutPosition + cutRadius);
    path.arcToPoint(
      Offset(0, cutPosition - cutRadius),
      radius: Radius.circular(cutRadius),
      clockwise: false,
    );
    path.close();

    // Draw shadow
    canvas.drawShadow(path, Colors.black.withOpacity(0.06), 5.0, true);

    // Fill with white
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.grey[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, borderPaint);

    // Draw dashed divider line between notches
    final dashPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double startX = cutRadius;
    final endX = size.width - cutRadius;
    while (startX < endX) {
      canvas.drawLine(
        Offset(startX, cutPosition),
        Offset(startX + dashWidth, cutPosition),
        dashPaint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DashedArcPainter extends CustomPainter {
  final Color color;
  DashedArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Start dot at y = 28, end dot at y = 28. Control point at y = 4 (for curve upwards)
    final p0 = Offset(6, 28);
    final p1 = Offset(size.width / 2, 4);
    final p2 = Offset(size.width - 6, 28);

    // Approximate bezier path
    const steps = 30;
    List<Offset> points = [];
    for (int i = 0; i <= steps; i++) {
      double t = i / steps;
      double x = (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
      double y = (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
      points.add(Offset(x, y));
    }

    // Draw dashes
    bool draw = true;
    double accumulatedLength = 0;
    const dashLength = 4.0;
    const gapLength = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      final pA = points[i];
      final pB = points[i + 1];
      final segmentLength = (pB - pA).distance;

      accumulatedLength += segmentLength;
      if (draw) {
        if (accumulatedLength >= dashLength) {
          canvas.drawLine(pA, pB, paint);
          accumulatedLength = 0;
          draw = false;
        } else {
          canvas.drawLine(pA, pB, paint);
        }
      } else {
        if (accumulatedLength >= gapLength) {
          accumulatedLength = 0;
          draw = true;
        }
      }
    }

    // Draw start and end dots with inner/outer rings
    final dotPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
      
    final dotOuterPaint = Paint()
      ..color = Colors.grey[200]!
      ..style = PaintingStyle.fill;

    canvas.drawCircle(p0, 4.0, dotOuterPaint);
    canvas.drawCircle(p0, 2.0, dotPaint);

    canvas.drawCircle(p2, 4.0, dotOuterPaint);
    canvas.drawCircle(p2, 2.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}