import 'package:flutter/material.dart';
import '../services/profile_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const ProfileSetupScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController =
      TextEditingController();

  bool _isSaving = false;

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your display name.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ProfileService.saveDisplayName(name);

      if (!mounted) return;

      widget.onComplete();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save profile: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 85,
                  color: Color(0xFF00C2D1),
                ),

                const SizedBox(height: 25),

                const Text(
                  'Welcome to DisasterMesh',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Create your profile to start communicating '
                  'with nearby DisasterMesh users.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  'CHOOSE YOUR DISPLAY NAME',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _nameController,
                  maxLength: 25,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Enter your name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 25),

                ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _isSaving
                          ? 'Saving profile...'
                          : 'Continue',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}