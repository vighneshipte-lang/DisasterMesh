import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();

  String _privacySetting = 'Requests only';
  bool _notificationsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final displayName = await ProfileService.getDisplayName();

    if (!mounted) return;

    setState(() {
      _nameController.text = displayName ?? '';

      _privacySetting = prefs.getString('privacy_setting') ?? 'Requests only';

      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;

      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a display name.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await ProfileService.saveDisplayName(name);
    await prefs.setString('privacy_setting', _privacySetting);
    await prefs.setBool('notifications_enabled', _notificationsEnabled);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile settings saved successfully.')),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),

            Center(
              child: CircleAvatar(
                radius: 42,
                backgroundColor: AppColors.surface,
                child: const Icon(
                  Icons.person_outline,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Center(
              child: Text(
                'Your Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 8),

            const Center(
              child: Text(
                'Choose how other nearby users see you.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              'DISPLAY NAME',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _nameController,
              maxLength: 30,
              decoration: const InputDecoration(
                hintText: 'Enter your display name',
                prefixIcon: Icon(Icons.person_outline),
                counterText: '',
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'PRIVACY',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _privacySetting,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    icon: const Icon(Icons.expand_more),
                    items: const [
                      DropdownMenuItem(
                        value: 'Requests only',
                        child: Text('Message requests only'),
                      ),
                      DropdownMenuItem(
                        value: 'Everyone',
                        child: Text('Everyone'),
                      ),
                      DropdownMenuItem(value: 'Nobody', child: Text('Nobody')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _privacySetting = value;
                        });
                      }
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'NOTIFICATIONS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: SwitchListTile(
                value: _notificationsEnabled,
                activeThumbColor: AppColors.primary,
                title: const Text('Incoming messages'),
                subtitle: const Text(
                  'Receive notifications for messages and requests.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 32),

            ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Changes'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
