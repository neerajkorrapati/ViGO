import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String uid;
  final String name;
  final String email;
  final String profilePic;
  final String branch;
  final String regNo;
  final String phoneNumber;
  final String gender;

  UserModel({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    required this.profilePic,
    required this.branch,
    required this.regNo,
    required this.phoneNumber,
    required this.gender,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      id: doc.id,
      uid: data['uid'] ?? doc.id,
      name: data['name'] ?? 'Student',
      email: data['email'] ?? '',
      profilePic: data['profilePic'] ?? '',
      branch: data['branch'] ?? '',
      regNo: data['regNo'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      gender: data['gender'] ?? 'Not Specified',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'profilePic': profilePic,
      'branch': branch,
      'regNo': regNo,
      'phoneNumber': phoneNumber,
      'gender': gender,
    };
  }
}