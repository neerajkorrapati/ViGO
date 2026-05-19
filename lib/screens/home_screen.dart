import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/party_model.dart';
import '../widgets/party_card.dart';
import '../widgets/create_ride_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _service = FirestoreService();
  final AuthService _auth = AuthService();
  
  String _timeFilter = 'All Upcoming';
  String _vehicleFilter = 'All Vehicles';
  String _vacancyFilter = 'Any Vacancy';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vi Go", style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        // THIS IS THE MISSING LOGOUT BUTTON
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Logout',
            onPressed: () async {
              await _auth.signOut();
              // The AuthGate (in main.dart) will see the sign-out 
              // and automatically flip the screen to LoginScreen.
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRide(context),
        label: const Text("Post a Ride", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF1A53FF),
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildDropdown(_timeFilter, ['All Upcoming', 'Next 24 Hours'], (val) => setState(() => _timeFilter = val!)),
                  const SizedBox(width: 8),
                  _buildDropdown(_vehicleFilter, ['All Vehicles', 'Auto Only', 'Cab Only'], (val) => setState(() => _vehicleFilter = val!)),
                  const SizedBox(width: 8),
                  _buildDropdown(_vacancyFilter, ['Any Vacancy', '1 Seat', '2 Seats', '3+ Seats'], (val) => setState(() => _vacancyFilter = val!)),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<List<PartyModel>>(
              stream: _service.getActiveParties(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                List<PartyModel> filteredRides = snapshot.data!;

                if (_timeFilter == 'Next 24 Hours') {
                  final tomorrow = DateTime.now().add(const Duration(hours: 24));
                  filteredRides = filteredRides.where((party) => party.departureTime.isBefore(tomorrow)).toList();
                }

                if (_vehicleFilter == 'Auto Only') {
                  filteredRides = filteredRides.where((party) => party.vehicleType == 'auto').toList();
                } else if (_vehicleFilter == 'Cab Only') {
                  filteredRides = filteredRides.where((party) => party.vehicleType == 'cab').toList();
                }

                if (_vacancyFilter != 'Any Vacancy') {
                  filteredRides = filteredRides.where((party) {
                    if (_vacancyFilter == '1 Seat') return party.seatsLeft == 1;
                    if (_vacancyFilter == '2 Seats') return party.seatsLeft == 2;
                    if (_vacancyFilter == '3+ Seats') return party.seatsLeft >= 3;
                    return true;
                  }).toList();
                }

                if (filteredRides.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text("No rides match your filters."),
                        TextButton(onPressed: _resetFilters, child: const Text("Clear Filters")),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredRides.length,
                  itemBuilder: (context, index) => PartyCard(party: filteredRides[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, 
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), 
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _resetFilters() => setState(() { 
    _timeFilter = 'All Upcoming'; 
    _vehicleFilter = 'All Vehicles'; 
    _vacancyFilter = 'Any Vacancy'; 
  });

  void _showCreateRide(BuildContext context) {
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), 
      builder: (context) => const CreateRideSheet()
    );
  }
}