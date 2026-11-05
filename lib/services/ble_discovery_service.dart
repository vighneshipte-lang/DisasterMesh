
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/mesh_message.dart';
import 'profile_service.dart';

class BleDiscoveryService {
  static const String _serviceUuid =
      '6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a01';

  static const String _messageCharacteristicUuid =
      '6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a02';

  static const String _identityCharacteristicUuid =
      '6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a03';

  static const String _identityWriteCharacteristicUuid =
      '6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a04';

  static BluetoothDevice? _connectedDevice;
  static BluetoothCharacteristic? _messageCharacteristic;
  static Map<String, String>? _remoteIdentity;

  static bool _scanStartInProgress = false;

  static BluetoothDevice? get connectedDevice => _connectedDevice;

  static Map<String, String>? get remoteIdentity => _remoteIdentity == null
      ? null
      : Map<String, String>.from(_remoteIdentity!);

  static Future<void> startScanning() async {
    if (_scanStartInProgress) return;

    _scanStartInProgress = true;

    try {
      final supported = await FlutterBluePlus.isSupported;

      if (!supported) {
        throw Exception('BLE is not supported on this device.');
      }

      final state = await FlutterBluePlus.adapterState
          .firstWhere((state) => state != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 5));

      if (state != BluetoothAdapterState.on) {
        throw Exception('Please turn Bluetooth on.');
      }

      if (FlutterBluePlus.isScanningNow) return;

      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } finally {
      _scanStartInProgress = false;
    }
  }

  static Stream<List<ScanResult>> get scanResults =>
      FlutterBluePlus.scanResults;

  static Future<void> stopScanning() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  static bool get isScanning => FlutterBluePlus.isScanningNow;

  static Stream<bool> get scanningState => FlutterBluePlus.isScanning;

  static Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await stopScanning();

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );

      try {
        await device.requestMtu(512);
      } catch (_) {}

      final services = await device.discoverServices();

      final targetService = services.firstWhere(
        (service) => service.uuid == Guid(_serviceUuid),
        orElse: () => throw Exception('DisasterMesh service not found.'),
      );

      final messageCharacteristic = targetService.characteristics.firstWhere(
        (characteristic) =>
            characteristic.uuid == Guid(_messageCharacteristicUuid),
        orElse: () => throw Exception('Message characteristic not found.'),
      );

      if (!messageCharacteristic.properties.write) {
        throw Exception('Message characteristic does not support writing.');
      }

      final identityCharacteristic = targetService.characteristics.firstWhere(
        (characteristic) =>
            characteristic.uuid == Guid(_identityCharacteristicUuid),
        orElse: () => throw Exception('Identity characteristic not found.'),
      );

      if (!identityCharacteristic.properties.read) {
        throw Exception('Identity characteristic does not support reading.');
      }

      final identityBytes = await identityCharacteristic.read();

      final identityJson =
          jsonDecode(utf8.decode(identityBytes)) as Map<String, dynamic>;

      final remoteName = identityJson['name']?.toString().trim() ?? '';
      final remoteDeviceId =
          identityJson['deviceId']?.toString().trim() ?? '';

      if (remoteName.isEmpty || remoteDeviceId.isEmpty) {
        throw Exception('The remote phone returned an invalid identity.');
      }

      final identityWriteCharacteristic = targetService.characteristics
          .firstWhere(
        (characteristic) =>
            characteristic.uuid == Guid(_identityWriteCharacteristicUuid),
        orElse: () =>
            throw Exception('Identity write characteristic not found.'),
      );

      if (!identityWriteCharacteristic.properties.write) {
        throw Exception(
          'Identity write characteristic does not support writing.',
        );
      }

      final localName =
          await ProfileService.getDisplayName() ?? 'DisasterMesh User';

      final localDeviceId = await ProfileService.getDeviceId();

      final localIdentityJson = jsonEncode({
        'name': localName,
        'deviceId': localDeviceId,
      });

      await identityWriteCharacteristic.write(
        utf8.encode(localIdentityJson),
        withoutResponse: false,
      );

      _connectedDevice = device;
      _messageCharacteristic = messageCharacteristic;
      _remoteIdentity = {
        'name': remoteName,
        'deviceId': remoteDeviceId,
      };

      debugPrint('DisasterMesh: Connected to $remoteName ($remoteDeviceId)');

      debugPrint(
        'DisasterMesh: Sent local identity $localName ($localDeviceId)',
      );
    } catch (e) {
      try {
        await device.disconnect();
      } catch (_) {}

      _connectedDevice = null;
      _messageCharacteristic = null;
      _remoteIdentity = null;

      rethrow;
    }
  }

  static Future<void> sendMessage(String message) async {
    final characteristic = _messageCharacteristic;

    if (_connectedDevice == null || characteristic == null) {
      throw Exception('Connect to a device first.');
    }

    await characteristic.write(
      utf8.encode(message),
      withoutResponse: false,
    );
  }

  static Future<void> sendMeshMessage(MeshMessage message) async {
    await sendMessage(message.toJson());
  }

  static Future<void> disconnectDevice() async {
    final device = _connectedDevice;

    _connectedDevice = null;
    _messageCharacteristic = null;
    _remoteIdentity = null;

    if (device != null) {
      await device.disconnect();
    }
  }

  static bool get isConnected =>
      _connectedDevice != null && _messageCharacteristic != null;
}
