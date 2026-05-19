import 'package:flutter/material.dart';
import '../models/party_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class CreateRideSheet extends StatefulWidget {
  const CreateRideSheet({super.key});

  @override
  State<CreateRideSheet> createState() => _CreateRideSheetState();
}

class _CreateRideSheetState extends State<CreateRideSheet> {
  final _destinationController = TextEditingController();
  final _pickupController = TextEditingController(text: "VIT Main Gate"); 
  final AuthService _auth = AuthService();
  
  int _selectedVehicleIndex = 0; 
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isLoading = false;

  Future<void> _submitRide() async {
    final String? uid = _auth.currentUserId;
    
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Not logged in")));
      return;
    }

    if (_destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a destination")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserModel? currentUser = await _auth.getUserProfile(uid);
      
      // This is likely where your 'null' error was coming from
      if (currentUser == null) {
        throw Exception("Profile not found. Please log out and back in.");
      }

      final newParty = PartyModel(
        id: '', 
        hostId: uid,
        pickup: _pickupController.text.trim(),
        destination: _destinationController.text.trim(),
        vehicleType: _selectedVehicleIndex == 0 ? 'auto' : 'cab',
        totalSeats: _selectedVehicleIndex == 0 ? 3 : 4,
        departureTime: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute),
        passengers: [
          {
            'id': currentUser.id,
            'name': currentUser.name,
            'phoneNumber': currentUser.phoneNumber,
            'gender': currentUser.gender
          }
        ],
      );

      await FirestoreService().createParty(newParty);
      if (mounted) Navigator.pop(context); 
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Post a New Ride", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          TextField(controller: _destinationController, decoration: const InputDecoration(labelText: "Where to?", border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _pickupController, decoration: const InputDecoration(labelText: "Pickup", border: OutlineInputBorder())),
          const SizedBox(height: 24),
          Row(
            children: [
              _vehicleTile(0, Icons.electric_rickshaw, "Auto"),
              const SizedBox(width: 12),
              _vehicleTile(1, Icons.local_taxi, "Cab"),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _pickerTile("${_selectedDate.day}/${_selectedDate.month}", Icons.calendar_today, () => _selectDate(context)),
              const SizedBox(width: 12),
              _pickerTile(_selectedTime.format(context), Icons.access_time, () => _selectTime(context)),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A53FF), foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _submitRide, 
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("POST RIDE")
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _vehicleTile(int index, IconData icon, String label) {
    bool selected = _selectedVehicleIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedVehicleIndex = index),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: selected ? const Color(0xFF1A53FF) : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [Icon(icon, color: selected ? Colors.white : Colors.black54), Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black54))]),
        ),
      ),
    );
  }

  Widget _pickerTile(String text, IconData icon, VoidCallback onTap) {
    return Expanded(child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(text)));
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }
}