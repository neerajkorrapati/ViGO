import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class Ride {
  final String id;
  final String driverName;
  final String driverId;
  final String destination;
  final String pickupPoint;
  final DateTime departureTime;
  final int totalSeats;
  final List<String> passengerIds;

  Ride({
    required this.id,
    required this.driverName,
    required this.driverId,
    required this.destination,
    required this.pickupPoint,
    required this.departureTime,
    required this.totalSeats,
    required this.passengerIds,
  });

  int get availableSeats => totalSeats - passengerIds.length;

  factory Ride.fromFirestore(DocumentSnapshot doc) {
    try {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
      return Ride(
        id: doc.id,
        driverName: data['driverName'] ?? 'Anonymous',
        driverId: data['driverId'] ?? '',
        destination: data['destination'] ?? 'Main Gate',
        pickupPoint: data['pickupPoint'] ?? 'Hostel',
        departureTime: data['departureTime'] != null 
            ? (data['departureTime'] as Timestamp).toDate() 
            : DateTime.now(),
        totalSeats: data['totalSeats'] ?? 4,
        passengerIds: List<String>.from(data['passengerIds'] ?? []),
      );
    } catch (e) {
      debugPrint("Error parsing ride ${doc.id}: $e");
      return Ride(
        id: doc.id,
        driverName: "Data Error",
        driverId: "",
        destination: "N/A",
        pickupPoint: "N/A",
        departureTime: DateTime.now(),
        totalSeats: 0,
        passengerIds: [],
      );
    }
  }
}