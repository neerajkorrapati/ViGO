import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/party_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<PartyModel>> getActiveParties() {
    return _db
        .collection('parties')
        .where('departureTime', isGreaterThan: Timestamp.now())
        .orderBy('departureTime')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PartyModel.fromFirestore(doc))
            .toList());
  }

  Future<void> createParty(PartyModel party) async {
    await _db.collection('parties').add(party.toJson());
  }

  // PHASE 2: Add a specific user to the passengers array
  Future<void> joinParty(String partyId, Map<String, dynamic> passengerData) async {
    await _db.collection('parties').doc(partyId).update({
      'passengers': FieldValue.arrayUnion([passengerData]),
    });
  }

  // Remove a user from the passengers array. We perform a transaction to
  // ensure we remove the exact passenger object stored in the array.
  Future<void> leaveParty(String partyId, String userId) async {
    final docRef = _db.collection('parties').doc(partyId);
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists) throw Exception('Party not found');

      final passengers = List<Map<String, dynamic>>.from(snapshot.get('passengers') ?? []);
      final passenger = passengers.firstWhere((p) => p['id'] == userId, orElse: () => {});
      if (passenger.isEmpty) return;

      tx.update(docRef, {
        'passengers': FieldValue.arrayRemove([passenger])
      });
    });
  }

  Future<void> deleteParty(String partyId) async {
    await _db.collection('parties').doc(partyId).delete();
  }
}