import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'ride_list_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _branchController = TextEditingController();
  final _regNoController = TextEditingController();
  final _phoneController = TextEditingController();
  String _gender = 'Male';

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final newUser = UserModel(
        id: user.uid,
        uid: user.uid,
        name: user.displayName ?? 'Student',
        email: user.email ?? '',
        profilePic: user.photoURL ?? '',
        branch: _branchController.text.trim(),
        regNo: _regNoController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        gender: _gender,
      );

      await _authService.createUserProfile(newUser);
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RideListScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(32), children: [
        const Text("Profile Setup", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        TextFormField(controller: _regNoController, decoration: const InputDecoration(labelText: "Reg No")),
        TextFormField(controller: _branchController, decoration: const InputDecoration(labelText: "Branch")),
        TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: "Phone")),
        DropdownButtonFormField<String>(initialValue: _gender, items: ['Male', 'Female'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(), onChanged: (v) => setState(() => _gender = v!)),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: _submit, child: const Text("Save and Continue")),
      ])),
    );
  }
}