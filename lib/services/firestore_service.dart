import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/party_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Fetches only upcoming rides, sorted by nearest time
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

  // Create a real party from the UI form
  Future<void> createParty(PartyModel party) async {
    await _db.collection('parties').add(party.toJson());
  }

  // Logic to join a party (increments seat count)
  Future<void> joinParty(String partyId) async {
    await _db.collection('parties').doc(partyId).update({
      'filledSeats': FieldValue.increment(1),
    });
  }
}