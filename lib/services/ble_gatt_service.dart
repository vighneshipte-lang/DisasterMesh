
import 'package:flutter/services.dart';

import '../models/mesh_message.dart';
import 'profile_service.dart';

class BleGattService {
  static const MethodChannel _methodChannel = MethodChannel(
    'disaster_mesh/ble_advertising',
  );

  static const EventChannel _eventChannel = EventChannel(
    'disaster_mesh/ble_messages',
  );

  // Send this phone's profile identity to the native Android layer.
  static Future<bool> setLocalIdentity() async {
    try {
      final name = await ProfileService.getDisplayName();
      final deviceId = await ProfileService.getDeviceId();

      final result = await _methodChannel.invokeMethod<bool>(
        'setIdentity',
        {
          'name': name ?? 'DisasterMesh User',
          'deviceId': deviceId,
        },
      );

      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception(
        'Unable to set local identity: ${e.message ?? e.code}',
      );
    }
  }

  // Tell Android which conversation is currently open.
  static Future<void> setActiveChat(String conversationId) async {
    try {
      await _methodChannel.invokeMethod<bool>(
        'setActiveChat',
        {
          'conversationId': conversationId,
        },
      );
    } on PlatformException catch (e) {
      throw Exception(
        'Unable to set active chat: ${e.message ?? e.code}',
      );
    }
  }

  // Tell Android that no conversation is currently open.
  static Future<void> clearActiveChat() async {
    try {
      await _methodChannel.invokeMethod<bool>('clearActiveChat');
    } on PlatformException catch (e) {
      throw Exception(
        'Unable to clear active chat: ${e.message ?? e.code}',
      );
    }
  }

  static Future<bool> startGattServer() async {
    try {
      // Identity must be ready before the GATT server starts.
      await setLocalIdentity();

      final result =
          await _methodChannel.invokeMethod<bool>('startGattServer');

      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception(
        'Unable to start GATT server: ${e.message ?? e.code}',
      );
    }
  }

  static Future<bool> stopGattServer() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('stopGattServer');

      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception(
        'Unable to stop GATT server: ${e.message ?? e.code}',
      );
    }
  }

  // Structured incoming BLE events.
  static Stream<Map<String, dynamic>> get receivedMessageEvents {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  // Keep the existing raw-message stream for compatibility.
  static Stream<String> get receivedMessages {
    return receivedMessageEvents.map(
      (event) => event['message']?.toString() ?? '',
    );
  }

  static Stream<MeshMessage> get receivedMeshMessages {
    return receivedMessages.map(
      (message) => MeshMessage.fromJson(message),
    );
  }
}
