
import 'package:flutter/material.dart';
import 'dart:async';

import 'offline_maps_screen.dart';
import '../services/sos_light_service.dart';
import '../services/emergency_whistle_service.dart';
import '../services/flashlight_service.dart';
import '../theme/app_theme.dart';
import '../widgets/emergency_tool_card.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;

  const HomeScreen({
    super.key,
    required this.onNavigate,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  bool _isFlashlightOn = false;
  bool _isSOSActive = false;
  bool _isWhistleActive = false;

  Future<void> _toggleWhistle() async {
    if (_isWhistleActive) {
      await EmergencyWhistleService.stopWhistle();

      if (!mounted) return;
      setState(() => _isWhistleActive = false);
    } else {
      try {
        await EmergencyWhistleService.startWhistle();

        if (!mounted) return;
        setState(() => _isWhistleActive = true);
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to play emergency whistle.'),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopEmergencyLights());
    }
  }

  Future<void> _stopEmergencyLights() async {
    await SosLightService.stopSOS();
    await FlashlightService.turnOff();
    await EmergencyWhistleService.stopWhistle();

    if (!mounted) return;

    setState(() {
      _isSOSActive = false;
      _isFlashlightOn = false;
      _isWhistleActive = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopEmergencyLights());
    super.dispose();
  }

  Future<void> _toggleSOS() async {
    if (_isSOSActive) {
      await SosLightService.stopSOS();

      if (!mounted) return;
      setState(() => _isSOSActive = false);
      return;
    }

    if (_isFlashlightOn) {
      await FlashlightService.turnOff();
      if (!mounted) return;
      setState(() => _isFlashlightOn = false);
    }

    setState(() => _isSOSActive = true);
    unawaited(SosLightService.startSOS());
  }

  Future<void> _toggleFlashlight() async {
    final success = _isFlashlightOn
        ? await FlashlightService.turnOff()
        : await FlashlightService.turnOn();

    if (!mounted) return;

    if (success) {
      setState(() {
        _isFlashlightOn = !_isFlashlightOn;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to control the flashlight.'),
        ),
      );
    }
  }

  void _showFeatureMessage(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature will be connected in the next step.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.hub_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DisasterMesh',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Offline. Connected. Prepared.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        _showFeatureMessage(context, 'Profile'),
                    icon: const Icon(
                      Icons.account_circle_outlined,
                      size: 30,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // CONNECTION STATUS
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.bluetooth_connected,
                      color: AppColors.success,
                      size: 25,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DisasterMesh',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Checking connection status...',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.circle,
                      color: AppColors.warning,
                      size: 10,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // EMERGENCY TOOLS
              const Text(
                'Emergency Tools',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'Essential tools when you need them.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 18),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,

                // Give cards more vertical space on smaller phones.
                childAspectRatio: screenWidth < 380 ? 0.85 : 0.95,

                children: [
                  EmergencyToolCard(
                    title: _isFlashlightOn
                        ? 'Flashlight ON'
                        : 'Flashlight',
                    subtitle: _isFlashlightOn
                        ? 'Tap to turn off'
                        : 'Illuminate your surroundings',
                    icon: _isFlashlightOn
                        ? Icons.flashlight_off_rounded
                        : Icons.flashlight_on_rounded,
                    iconColor: const Color(0xFFFFD166),
                    onTap: _toggleFlashlight,
                  ),
                  EmergencyToolCard(
                    title: _isSOSActive ? 'Stop SOS' : 'SOS Light',
                    subtitle: _isSOSActive
                        ? 'SOS signal is active. Tap to stop.'
                        : 'Flash an SOS emergency signal',
                    icon: _isSOSActive
                        ? Icons.stop_circle
                        : Icons.sos,
                    iconColor: AppColors.emergency,
                    onTap: _toggleSOS,
                  ),
                  EmergencyToolCard(
                    title: _isWhistleActive
                        ? 'Stop Whistle'
                        : 'Emergency Whistle',
                    subtitle: _isWhistleActive
                        ? 'Whistle is playing. Tap to stop.'
                        : 'Play a loud emergency whistle',
                    icon: _isWhistleActive
                        ? Icons.stop_circle
                        : Icons.campaign,
                    iconColor: AppColors.warning,
                    onTap: _toggleWhistle,
                  ),
                  EmergencyToolCard(
                    title: 'Offline Maps',
                    subtitle: 'Access saved maps',
                    icon: Icons.map_rounded,
                    iconColor: AppColors.success,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const OfflineMapsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // COMMUNICATION
              const Text(
                'Communication',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              _communicationTile(
                context,
                icon: Icons.people_alt_rounded,
                title: 'Find Nearby',
                subtitle: 'Discover people around you',
                onTap: () => widget.onNavigate(1),
              ),

              const SizedBox(height: 12),

              _communicationTile(
                context,
                icon: Icons.message_rounded,
                title: 'Messages',
                subtitle: 'Communicate without internet',
                onTap: () => widget.onNavigate(2),
              ),

              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  Widget _communicationTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
