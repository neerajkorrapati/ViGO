import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _vehicleType = 'Auto';
  String? _pickupPoint;
  String? _destination;
  int _availableSeats = 3;
  bool _isLoading = false;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  final _notesController = TextEditingController();

  final List<String> _locations = [
    "VIT Vellore Main Gate",
    "Katpadi Railway Station",
    "New Bus Stand",
    "Vellore Bypass / Near DTDC",
    "Bangalore Airport",
    "Chennai Airport",
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatDateDisplay() {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${_selectedDate.day} ${months[_selectedDate.month - 1]} ${_selectedDate.year}";
  }

  String _formatTimeDisplay() {
    final String period = _selectedTime.period == DayPeriod.am ? "AM" : "PM";
    final int hour = _selectedTime.hourOfPeriod == 0 ? 12 : _selectedTime.hourOfPeriod;
    final String minute = _selectedTime.minute.toString().padLeft(2, '0');
    return "$hour:$minute $period";
  }

  void _handleVehicleToggle(String type) {
    setState(() {
      _vehicleType = type;
      _availableSeats = (type == 'Cab') ? 4 : 3;
    });
  }

  Future<void> _publishRideToFirebase() async {
    if (!_formKey.currentState!.validate()) return;

    final DateTime departureTimestamp = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (departureTimestamp.isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      _showWarningSnackBar("Departure schedule cannot point to a past timestamp.");
      return;
    }

    if (_pickupPoint == _destination) {
      _showWarningSnackBar("Your pickup point and destination point cannot match.(Why would u wanna go to the same place from the same place xD!");
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final userProfileDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final String verifiedPhoneNumber = userProfileDoc.data()?['phoneNumber'] ?? '';

      await FirebaseFirestore.instance.collection('rides').add({
        'driverName': user.displayName ?? 'VIT Student',
        'driverId': user.uid,
        'driverPhone': verifiedPhoneNumber,
        'pickupPoint': _pickupPoint,
        'destination': _destination,
        'totalSeats': _availableSeats,
        'vehicleType': _vehicleType,
        'departureTime': Timestamp.fromDate(departureTimestamp),
        'journeyNotes': _notesController.text.trim(),
        'passengerIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ride route published live to campus feed!"), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Submission failed: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showWarningSnackBar(String alertMsg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(alertMsg), backgroundColor: Colors.orangeAccent, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Offer a Ride", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Mode of Transport", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 10),
                    Row(
                      children: ['Auto', 'Cab'].map((type) {
                        final isSelected = _vehicleType == type;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _handleVehicleToggle(type),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.indigo : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? Colors.indigo : Colors.grey[200]!, width: 2),
                                boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  Icon(type == 'Auto' ? Icons.electric_rickshaw : Icons.local_taxi, color: isSelected ? Colors.white : Colors.indigo, size: 36),
                                  const SizedBox(height: 8),
                                  Text(type, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    const Text("Route Information", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)],
                      ),
                      child: Column(
                        children: [
                          // FIXED: Swapped 'value' parameters with modern 'initialValue' configurations
                          DropdownButtonFormField<String>(
                            initialValue: _pickupPoint,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: "Pickup Point",
                              labelStyle: const TextStyle(color: Colors.grey),
                              prefixIcon: const Icon(Icons.radio_button_checked, color: Colors.indigo, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: const Color(0xFFF8F9FA),
                            ),
                            items: _locations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc, style: const TextStyle(fontSize: 14)))).toList(),
                            onChanged: (v) => setState(() => _pickupPoint = v),
                            validator: (v) => v == null ? "Please assign an initial pickup hub" : null,
                          ),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                            initialValue: _destination,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: "Destination Location",
                              labelStyle: const TextStyle(color: Colors.grey),
                              prefixIcon: const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: const Color(0xFFF8F9FA),
                            ),
                            items: _locations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc, style: const TextStyle(fontSize: 14)))).toList(),
                            onChanged: (v) => setState(() => _destination = v),
                            validator: (v) => v == null ? "Please assign a target destination transit" : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    const Text("Departure Schedule", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 30)),
                              );
                              if (pickedDate != null) setState(() => _selectedDate = pickedDate);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month, color: Colors.indigo, size: 20),
                                  const SizedBox(width: 10),
                                  Text(_formatDateDisplay(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedTime = await showTimePicker(context: context, initialTime: _selectedTime);
                              if (pickedTime != null) setState(() => _selectedTime = pickedTime);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_filled, color: Colors.indigo, size: 20),
                                  const SizedBox(width: 10),
                                  Text(_formatTimeDisplay(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[100]!)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Available Seats Allocation", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              SizedBox(height: 2),
                              Text("Scale space requirements as needed", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _availableSeats > 1 ? () => setState(() => _availableSeats--) : null,
                                icon: const Icon(Icons.remove_circle, size: 30, color: Colors.indigo),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text("$_availableSeats", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                onPressed: _availableSeats < ((_vehicleType == 'Cab') ? 7 : 4) ? () => setState(() => _availableSeats++) : null,
                                icon: const Icon(Icons.add_circle, size: 30, color: Colors.indigo),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    const Text("Journey Notes (Optional)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      maxLength: 150,
                      decoration: InputDecoration(
                        hintText: "E.g., Waiting near Block L gate. Max 1 backpack per person. Splitting auto fare equally.",
                        hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _publishRideToFirebase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text("Publish Ride Feed", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}