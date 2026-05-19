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

  Future<void> deleteParty(String partyId) async {
    await _db.collection('parties').doc(partyId).delete();
  }
}