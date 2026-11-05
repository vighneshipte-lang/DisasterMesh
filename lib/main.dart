import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;

import 'dart:async';

import 'services/ble_advertising_service.dart';
import 'services/message_reception_service.dart';
import 'screens/nearby_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/chat_screen.dart';
import 'services/profile_service.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'services/device_identity.dart';
import 'services/bluetooth_permission_service.dart';
import 'services/bluetooth_service.dart';
import 'services/ble_discovery_service.dart';
import 'services/ble_gatt_service.dart';

const MethodChannel _notificationMethodChannel = MethodChannel(
  'disaster_mesh/ble_advertising',
);

const EventChannel _notificationEventChannel = EventChannel(
  'disaster_mesh/notification_navigation',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.initialize();

  runApp(const DisasterMeshApp());
}

class DisasterMeshApp extends StatelessWidget {
  const DisasterMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DisasterMesh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const StartupScreen(),
    );
  }
}

// ============================================================================
// STARTUP SCREEN
// ============================================================================

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _isLoading = true;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final name = await ProfileService.getDisplayName();

    if (!mounted) return;

    setState(() {
      _hasProfile = name != null;
      _isLoading = false;
    });
  }

  void _completeSetup() {
    setState(() {
      _hasProfile = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasProfile) {
      return ProfileSetupScreen(onComplete: _completeSetup);
    }

    return const MainNavigationScreen();
  }
}

// ============================================================================
// MAIN NAVIGATION SCREEN
// ============================================================================

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  StreamSubscription<dynamic>? _notificationSubscription;

  bool _isOpeningNotificationChat = false;

  late final List<Widget> _screens = [
    HomeScreen(
      onNavigate: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    ),
    const NearbyScreen(),
    const MessagesScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();

    MessageReceptionService.start();

    _listenForNotificationTaps();
  }

  // Listen for notification taps while the app is running.
  Future<void> _listenForNotificationTaps() async {
    _notificationSubscription = _notificationEventChannel
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (event is Map) {
              _openNotificationChat(
                event['conversationId']?.toString(),
                event['displayName']?.toString(),
              );
            }
          },
          onError: (error) {
            debugPrint('Notification event error: $error');
          },
        );

    // Check whether Android launched the app from a notification.
    try {
      final initialData = await _notificationMethodChannel
          .invokeMethod<dynamic>('getInitialNotification');

      if (initialData is Map) {
        _openNotificationChat(
          initialData['conversationId']?.toString(),
          initialData['displayName']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('Initial notification check failed: $e');
    }
  }

  // Navigate directly to the sender's chat.
  void _openNotificationChat(String? conversationId, String? displayName) {
    if (conversationId == null || conversationId.trim().isEmpty || !mounted) {
      return;
    }

    if (_isOpeningNotificationChat) return;

    _isOpeningNotificationChat = true;

    final contactId = conversationId.trim();

    final contactName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : 'Nearby device';

    // Select the Messages tab.
    setState(() {
      _selectedIndex = 2;
    });

    // Wait until the Messages tab is displayed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isOpeningNotificationChat = false;
        return;
      }

      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(contactName: contactName, contactId: contactId),
            ),
          )
          .whenComplete(() {
            _isOpeningNotificationChat = false;
          });
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();

    MessageReceptionService.stop();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Nearby',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DEVICE SETUP SCREEN
// ============================================================================

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  bool _isChecking = false;
  bool? _permissionGranted;
  bool _isAdvertising = false;
  bool _isGattServerRunning = false;
  bool _isConnecting = false;
  String? _connectedDeviceId;

  final TextEditingController _messageController = TextEditingController();

  final List<String> _receivedMessages = [];

  StreamSubscription<String>? _messageSubscription;

  Future<void> _sendTestMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty) return;

    try {
      await BleDiscoveryService.sendMessage(message);

      if (!mounted) return;

      _messageController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent successfully!')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Message sending failed: $e')));
    }
  }

  Future<void> _startGattServer() async {
    try {
      final started = await BleGattService.startGattServer();

      if (!mounted) return;

      setState(() {
        _isGattServerRunning = started;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            started
                ? 'DisasterMesh GATT server started!'
                : 'Unable to start GATT server.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
    });

    try {
      await BleDiscoveryService.connectToDevice(device);

      if (!mounted) return;

      setState(() {
        _connectedDeviceId = device.remoteId.str;
        _isConnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.platformName}!')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _connectedDeviceId = null;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Connection failed: $e')));
    }
  }

  Future<void> _disconnectDevice() async {
    try {
      await BleDiscoveryService.disconnectDevice();

      if (!mounted) return;

      setState(() {
        _connectedDeviceId = null;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Device disconnected.')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Disconnection failed: $e')));
    }
  }

  Future<void> _stopGattServer() async {
    try {
      await BleGattService.stopGattServer();

      if (!mounted) return;

      setState(() {
        _isGattServerRunning = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('GATT server stopped.')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _checkBluetoothStatus() async {
    final status = await BluetoothService.getBluetoothStatus();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
  }

  Future<void> _requestBluetoothPermission() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final granted = await BluetoothPermissionService.requestPermissions();

      if (!mounted) return;

      setState(() {
        _permissionGranted = granted;
        _isChecking = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isChecking = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _startBleScan() async {
    final permissionsGranted =
        await BluetoothPermissionService.arePermissionsGranted();

    if (!mounted) return;

    if (!permissionsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permissions are required.')),
      );
      return;
    }

    try {
      await BleDiscoveryService.startScanning();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _stopBleScan() async {
    try {
      await BleDiscoveryService.stopScanning();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _startBleAdvertising() async {
    final permissionsGranted =
        await BluetoothPermissionService.arePermissionsGranted();

    if (!mounted) return;

    if (!permissionsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permissions are required.')),
      );
      return;
    }

    try {
      final started = await BleAdvertisingService.startAdvertising();

      if (!mounted) return;

      setState(() {
        _isAdvertising = started;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            started
                ? 'DisasterMesh advertising started!'
                : 'Unable to start advertising.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _stopBleAdvertising() async {
    try {
      await BleAdvertisingService.stopAdvertising();

      if (!mounted) return;

      setState(() {
        _isAdvertising = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DisasterMesh advertising stopped.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  void initState() {
    super.initState();

    _messageSubscription = BleGattService.receivedMessages.listen((message) {
      if (!mounted) return;

      setState(() {
        _receivedMessages.add(message);
      });
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DisasterMesh',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF111C2E),
      ),
      body: FutureBuilder<String>(
        future: DeviceIdentity.getDeviceId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to create device identity.'),
            );
          }

          final deviceId = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 25),

                const Icon(
                  Icons.shield_outlined,
                  size: 75,
                  color: Color(0xFF00C2D1),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Welcome to DisasterMesh',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Your offline emergency communication network.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.white70),
                ),

                const SizedBox(height: 35),

                const Text(
                  'YOUR DEVICE ID',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF172438),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00C2D1)),
                  ),
                  child: SelectableText(
                    deviceId,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),

                const SizedBox(height: 35),

                const Text(
                  'ENABLE BLUETOOTH ACCESS',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton(
                  onPressed: () async {
                    final granted =
                        await BluetoothPermissionService.arePermissionsGranted();

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          granted
                              ? 'All Bluetooth permissions granted!'
                              : 'Some Bluetooth permissions are missing.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Check Permissions'),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _checkBluetoothStatus,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Check Bluetooth Status'),
                ),

                const SizedBox(height: 12),

                const Text(
                  'DisasterMesh uses Bluetooth to discover nearby '
                  'phones and transfer emergency messages between '
                  'devices, even when internet access is unavailable.',
                  style: TextStyle(color: Colors.white70, height: 1.5),
                ),

                const SizedBox(height: 20),

                ElevatedButton.icon(
                  onPressed: _isChecking ? null : _requestBluetoothPermission,
                  icon: const Icon(Icons.bluetooth),
                  label: Text(
                    _isChecking
                        ? 'Checking permissions...'
                        : 'Allow Bluetooth Access',
                  ),
                ),

                if (_permissionGranted == true) ...[
                  const SizedBox(height: 15),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.greenAccent),
                      SizedBox(width: 8),
                      Text('Bluetooth permissions granted'),
                    ],
                  ),
                ],

                if (_permissionGranted == false) ...[
                  const SizedBox(height: 15),
                  const Text(
                    'Bluetooth permissions were not granted. '
                    'You can try again or enable them in app settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                  TextButton(
                    onPressed: BluetoothPermissionService.openSettings,
                    child: const Text('Open App Settings'),
                  ),
                ],

                const SizedBox(height: 30),

                const Text(
                  'BLE ADVERTISING',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: _isAdvertising ? null : _startBleAdvertising,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Start Advertising'),
                ),

                OutlinedButton.icon(
                  onPressed: _isAdvertising ? _stopBleAdvertising : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Advertising'),
                ),

                Text(
                  _isAdvertising
                      ? 'DisasterMesh is broadcasting its Bluetooth signal.'
                      : 'Advertising is currently inactive.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),

                const SizedBox(height: 25),

                const Text(
                  'GATT COMMUNICATION',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: _isGattServerRunning ? null : _startGattServer,
                  icon: const Icon(Icons.dns),
                  label: const Text('Start GATT Server'),
                ),

                OutlinedButton.icon(
                  onPressed: _isGattServerRunning ? _stopGattServer : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop GATT Server'),
                ),

                Text(
                  _isGattServerRunning
                      ? 'GATT Server is running.'
                      : 'GATT Server is stopped.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),

                const SizedBox(height: 30),

                const Text(
                  'NEARBY DEVICES',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                StreamBuilder<bool>(
                  stream: BleDiscoveryService.scanningState,
                  initialData: BleDiscoveryService.isScanning,
                  builder: (context, snapshot) {
                    final scanning = snapshot.data ?? false;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: scanning ? null : _startBleScan,
                          icon: const Icon(Icons.search),
                          label: const Text('Scan Nearby Devices'),
                        ),

                        OutlinedButton.icon(
                          onPressed: scanning ? _stopBleScan : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Scanning'),
                        ),

                        Text(
                          scanning
                              ? 'Scanning for nearby Bluetooth devices...'
                              : 'Scanner is idle.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 15),

                StreamBuilder(
                  stream: BleDiscoveryService.scanResults,
                  builder: (context, snapshot) {
                    final results = snapshot.data;

                    if (results == null || results.isEmpty) {
                      return const Text(
                        'No devices discovered yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      );
                    }

                    return Column(
                      children: results.map((result) {
                        final name = result.device.platformName.isNotEmpty
                            ? result.device.platformName
                            : 'Unknown device';

                        return Card(
                          color: const Color(0xFF172438),
                          child: ListTile(
                            leading: const Icon(
                              Icons.bluetooth,
                              color: Color(0xFF00C2D1),
                            ),
                            title: Text(name),
                            subtitle: Text(
                              'Device ID: '
                              '${result.device.remoteId.str}',
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${result.rssi} dBm',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 5),
                                if (_connectedDeviceId ==
                                    result.device.remoteId.str)
                                  const Text(
                                    'Connected',
                                    style: TextStyle(color: Colors.greenAccent),
                                  )
                                else
                                  TextButton(
                                    onPressed: _isConnecting
                                        ? null
                                        : () => _connectToDevice(result.device),
                                    child: Text(
                                      _isConnecting
                                          ? 'Connecting...'
                                          : 'Connect',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                if (_connectedDeviceId != null) ...[
                  const SizedBox(height: 15),
                  Text(
                    'Connected to: $_connectedDeviceId',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _disconnectDevice,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect Device'),
                  ),
                ],

                const SizedBox(height: 25),

                const Text(
                  'OFFLINE MESSAGING',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                if (_connectedDeviceId != null) ...[
                  TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Enter your message...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.message),
                    ),
                    maxLength: 500,
                  ),

                  ElevatedButton.icon(
                    onPressed: _sendTestMessage,
                    icon: const Icon(Icons.send),
                    label: const Text('Send Message'),
                  ),
                ] else
                  const Text(
                    'Connect to another DisasterMesh device to send messages.',
                    style: TextStyle(color: Colors.white70),
                  ),

                const SizedBox(height: 20),

                const Text(
                  'RECEIVED MESSAGES',
                  style: TextStyle(
                    color: Color(0xFF00C2D1),
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                if (_receivedMessages.isEmpty)
                  const Text(
                    'No messages received yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  )
                else
                  ..._receivedMessages.map(
                    (message) => Card(
                      color: const Color(0xFF172438),
                      child: ListTile(
                        leading: const Icon(
                          Icons.mark_chat_unread,
                          color: Color(0xFF00C2D1),
                        ),
                        title: const Text('Received message'),
                        subtitle: Text(message),
                      ),
                    ),
                  ),

                const SizedBox(height: 25),
              ],
            ),
          );
        },
      ),
    );
  }
}
