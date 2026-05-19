import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '305617221299-akq1cc9bg76f97859lc2jlrht83p1u52.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  Stream<User?> get user => _auth.authStateChanges();
  String? get currentUserId => _auth.currentUser?.uid;

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      if (!googleUser.email.endsWith('@vitstudent.ac.in')) {
        await _googleSignIn.signOut();
        throw 'Use your @vitstudent.ac.in email.';
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async => await Future.wait([_googleSignIn.signOut(), _auth.signOut()]);

  Future<bool> isProfileComplete(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<void> createUserProfile(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists ? UserModel.fromFirestore(doc) : null;
  }
}