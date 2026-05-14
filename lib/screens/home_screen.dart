import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/party_model.dart';
import '../widgets/party_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vi Go", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRide(context, service),
        label: const Text("Post a Ride"),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF1A53FF),
      ),
      body: StreamBuilder<List<PartyModel>>(
        stream: service.getActiveParties(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) return const Center(child: Text("No active rides. Start one!"));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => PartyCard(party: snapshot.data![index]),
          );
        },
      ),
    );
  }

  void _showCreateRide(BuildContext context, FirestoreService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("New Ride", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            // Placeholder for form: You can add TextFields here
            ElevatedButton(
              onPressed: () {
                service.createParty(PartyModel(
                  id: '',
                  hostName: 'Neeraj',
                  phoneNumber: '919999999999',
                  pickup: 'Main Gate',
                  destination: 'Katpadi Station',
                  vehicleType: 'auto',
                  totalSeats: 3,
                  filledSeats: 1,
                  departureTime: DateTime.now().add(const Duration(minutes: 45)),
                ));
                Navigator.pop(context);
              },
              child: const Text("Submit Test Ride"),
            )
          ],
        ),
      ),
    );
  }
}