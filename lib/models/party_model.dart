import 'package:cloud_firestore/cloud_firestore.dart';

class PartyModel {
  final String id;
  final String hostName;
  final String phoneNumber;
  final String pickup;
  final String destination;
  final String vehicleType;
  final int totalSeats;
  final int filledSeats;
  final DateTime departureTime;

  PartyModel({
    required this.id,
    required this.hostName,
    required this.phoneNumber,
    required this.pickup,
    required this.destination,
    required this.vehicleType,
    required this.totalSeats,
    required this.filledSeats,
    required this.departureTime,
  });

  // Helper to calculate spots left for the UI
  int get seatsLeft => totalSeats - filledSeats;

  // Check if the ride is already full
  bool get isFull => filledSeats >= totalSeats;

  factory PartyModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PartyModel(
      id: doc.id,
      hostName: data['hostName'] ?? 'VIT Student',
      phoneNumber: data['phoneNumber'] ?? '',
      pickup: data['pickup'] ?? 'Main Gate',
      destination: data['destination'] ?? 'Katpadi Station',
      vehicleType: data['vehicleType'] ?? 'auto',
      totalSeats: data['totalSeats'] ?? 3,
      filledSeats: data['filledSeats'] ?? 1,
      departureTime: (data['departureTime'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hostName': hostName,
      'phoneNumber': phoneNumber,
      'pickup': pickup,
      'destination': destination,
      'vehicleType': vehicleType,
      'totalSeats': totalSeats,
      'filledSeats': filledSeats,
      'departureTime': Timestamp.fromDate(departureTime),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}