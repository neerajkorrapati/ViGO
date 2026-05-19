import 'package:cloud_firestore/cloud_firestore.dart';

class PartyModel {
  final String id;
  final String hostId;
  final String pickup;
  final String destination;
  final String vehicleType;
  final int totalSeats;
  final DateTime departureTime;
  final List<Map<String, dynamic>> passengers; 

  PartyModel({
    required this.id, required this.hostId, required this.pickup,
    required this.destination, required this.vehicleType,
    required this.totalSeats, required this.departureTime,
    required this.passengers,
  });

  int get seatsLeft => totalSeats - passengers.length;
  bool get isFull => passengers.length >= totalSeats;

  factory PartyModel.fromFirestore(DocumentSnapshot doc) {
    // Robust null checking for the entire document
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    
    return PartyModel(
      id: doc.id,
      hostId: data['hostId'] ?? '',
      pickup: data['pickup'] ?? 'Unknown',
      destination: data['destination'] ?? 'Unknown',
      vehicleType: data['vehicleType'] ?? 'auto',
      totalSeats: data['totalSeats'] ?? 3,
      // Handle potential null or missing timestamps
      departureTime: data['departureTime'] != null 
          ? (data['departureTime'] as Timestamp).toDate() 
          : DateTime.now(),
      passengers: List<Map<String, dynamic>>.from(data['passengers'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'hostId': hostId, 
    'pickup': pickup, 
    'destination': destination,
    'vehicleType': vehicleType, 
    'totalSeats': totalSeats,
    'departureTime': Timestamp.fromDate(departureTime),
    'passengers': passengers,
    'createdAt': FieldValue.serverTimestamp(),
  };
}