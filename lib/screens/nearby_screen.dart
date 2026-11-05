
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../theme/app_theme.dart';
import '../services/message_reception_service.dart';
import 'chat_screen.dart';
import '../services/ble_advertising_service.dart';
import '../services/ble_gatt_service.dart';
import '../services/ble_discovery_service.dart';
import '../services/bluetooth_permission_service.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  static const Duration _scanDuration = Duration(seconds: 10);

  bool _isConnecting = false;
  String? _connectedDeviceName;

  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _restoreConnection();
  }

  void _restoreConnection() {
    final device = BleDiscoveryService.connectedDevice;
    final identity = BleDiscoveryService.remoteIdentity;

    if (device != null && BleDiscoveryService.isConnected) {
      _connectedDeviceName = identity?['name'];

      debugPrint(
        'DisasterMesh: Restored connection to '
        '${_connectedDeviceName ?? device.remoteId.str}',
      );
    }
  }

  // Read the profile name from the BLE scan response.
  String? _getAdvertisedProfileName(ScanResult result) {
    try {
      final manufacturerData =
          result.advertisementData.manufacturerData;

      final profileBytes = manufacturerData[0xFFFF];

      if (profileBytes == null || profileBytes.isEmpty) {
        return null;
      }

      final name = utf8.decode(
        profileBytes,
        allowMalformed: true,
      ).trim();

      if (name.isEmpty) return null;

      return name;
    } catch (e) {
      debugPrint(
        'DisasterMesh: Unable to read advertised name: $e',
      );
      return null;
    }
  }

  Future<void> _startScanning() async {
    if (_isConnecting || BleDiscoveryService.isConnected) return;

    try {
      final granted =
          await BluetoothPermissionService.arePermissionsGranted();

      if (!mounted) return;

      if (!granted) {
        final requested =
            await BluetoothPermissionService.requestPermissions();

        if (!mounted) return;

        if (!requested) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth permissions are required.'),
            ),
          );
          return;
        }
      }

      final warnings = <String>[];

      // Start the GATT server so other phones can connect to this phone.
      try {
        final gattStarted =
            await BleGattService.startGattServer();

        if (!gattStarted) {
          warnings.add('GATT server did not start');
        }
      } catch (e) {
        warnings.add('$e');
      }

      // Keep advertising active even after scanning stops.
      try {
        final advertisingStarted =
            await BleAdvertisingService.startAdvertising();

        if (!advertisingStarted) {
          warnings.add('Advertising did not start');
        }
      } catch (e) {
        warnings.add('$e');
      }

      await BleDiscoveryService.startScanning();

      if (!mounted) return;

      _scanTimer?.cancel();

      // Automatically stop scanning after 10 seconds.
      _scanTimer = Timer(_scanDuration, () async {
        await _stopScanning();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nearby search completed.'),
            duration: Duration(seconds: 2),
          ),
        );
      });

      if (warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scanning, but others may not see you: '
              '${warnings.join('; ')}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start discovery: $e'),
        ),
      );
    }
  }

  Future<void> _stopScanning() async {
    _scanTimer?.cancel();
    _scanTimer = null;

    try {
      await BleDiscoveryService.stopScanning();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to stop scanning: $e'),
        ),
      );
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_isConnecting || BleDiscoveryService.isConnected) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      await _stopScanning();

      await BleDiscoveryService.connectToDevice(device);

      if (!mounted) return;

      final identity = BleDiscoveryService.remoteIdentity;

      if (identity == null) {
        throw Exception(
          'Remote profile identity was not received.',
        );
      }

      final contactName = identity['name']!;
      final contactId = identity['deviceId']!;

      MessageReceptionService.registerPeer(
        peerId: device.remoteId.str,
        contactName: contactName,
      );

      setState(() {
        _connectedDeviceName = contactName;
        _isConnecting = false;
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            contactName: contactName,
            contactId: contactId,
          ),
        ),
      );

      if (!mounted) return;

      // Preserve connection status when returning from chat.
      if (!BleDiscoveryService.isConnected) {
        setState(() {
          _connectedDeviceName = null;
        });
      } else {
        setState(() {
          _connectedDeviceName =
              BleDiscoveryService.remoteIdentity?['name'];
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _connectedDeviceName = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    try {
      await BleDiscoveryService.disconnectDevice();

      if (!mounted) return;

      setState(() {
        _connectedDeviceName = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Disconnection failed: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nearby',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'People around you',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Discover nearby DisasterMesh users and connect '
                'without an internet connection.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Scanning status.
              StreamBuilder<bool>(
                stream: BleDiscoveryService.scanningState,
                initialData: BleDiscoveryService.isScanning,
                builder: (context, snapshot) {
                  final scanning = snapshot.data ?? false;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          scanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth,
                          color: scanning
                              ? AppColors.success
                              : AppColors.textSecondary,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                scanning
                                    ? 'Searching for people'
                                    : 'Discovery is inactive',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                scanning
                                    ? 'Searching for 10 seconds...'
                                    : 'Start discovery to find nearby users.',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (scanning)
                          const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              // Find people and stop buttons.
              StreamBuilder<bool>(
                stream: BleDiscoveryService.scanningState,
                initialData: BleDiscoveryService.isScanning,
                builder: (context, snapshot) {
                  final scanning = snapshot.data ?? false;

                  return Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: scanning ||
                                  _isConnecting ||
                                  BleDiscoveryService.isConnected
                              ? null
                              : _startScanning,
                          icon: const Icon(Icons.search),
                          label: const Text('Find people'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed:
                            scanning ? _stopScanning : null,
                        child: const Icon(Icons.stop),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DISCOVERED DEVICES',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  StreamBuilder<List<ScanResult>>(
                    stream: BleDiscoveryService.scanResults,
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;

                      return Text(
                        '$count found',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Discovered devices.
              Expanded(
                child: StreamBuilder<List<ScanResult>>(
                  stream: BleDiscoveryService.scanResults,
                  builder: (context, snapshot) {
                    final results = snapshot.data;

                    if (results == null || results.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 58,
                              color:
                                  AppColors.textSecondary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No nearby devices yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap Find people to discover devices.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final result = results[index];

                        final advertisedName =
                            _getAdvertisedProfileName(result);

                        final bluetoothName =
                            result.device.platformName.isNotEmpty
                                ? result.device.platformName
                                : 'Unknown device';

                        final displayName =
                            advertisedName ?? bluetoothName;

                        final bluetoothId =
                            result.device.remoteId.str;

                        final serviceUuids = result
                            .advertisementData.serviceUuids
                            .map((uuid) => uuid.toString())
                            .toList();

                        final isDisasterMesh =
                            serviceUuids.any(
                          (uuid) =>
                              uuid.toLowerCase() ==
                              '6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a01',
                        );

                        final connected =
                            BleDiscoveryService.isConnected &&
                            BleDiscoveryService.connectedDevice
                                    ?.remoteId.str ==
                                bluetoothId;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: AppColors.surface,
                                child: const Icon(
                                  Icons.person,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Bluetooth ID: $bluetoothId\n'
                                      'RSSI: ${result.rssi} dBm',
                                      style: const TextStyle(
                                        color:
                                            AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (isDisasterMesh)
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          top: 5,
                                        ),
                                        child: Text(
                                          'DisasterMesh device detected',
                                          style: TextStyle(
                                            color: AppColors.success,
                                            fontWeight:
                                                FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (connected)
                                const Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                TextButton(
                                  onPressed: _isConnecting ||
                                          BleDiscoveryService
                                              .isConnected ||
                                          !isDisasterMesh
                                      ? null
                                      : () => _connect(
                                            result.device,
                                          ),
                                  child: Text(
                                    _isConnecting
                                        ? 'Connecting...'
                                        : 'Connect',
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Disconnect button.
              if (BleDiscoveryService.isConnected) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: Text(
                      'Disconnect${_connectedDeviceName == null ? '' : ' from $_connectedDeviceName'}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
