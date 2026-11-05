
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_gatt_service.dart';
import 'message_storage_service.dart';

class MessageReceptionService {
  static StreamSubscription<Map<String, dynamic>>? _subscription;

  // Contact names indexed by permanent DisasterMesh ID.
  static final Map<String, String> _contactNames = {};

  // Maps Android Bluetooth addresses to permanent DisasterMesh IDs.
  static final Map<String, String> _peerDeviceIds = {};

  // Temporary fallback for the currently active conversation.
  static String? _activePeerId;

  static bool get isListening => _subscription != null;

  static void registerPeer({
    required String peerId,
    required String contactName,
  }) {
    final normalizedId = peerId.toLowerCase();

    _contactNames[normalizedId] = contactName;
    _activePeerId = normalizedId;

    debugPrint(
      'DisasterMesh: Active peer registered: $normalizedId ($contactName)',
    );
  }

  // Process identity received from another phone.
  static void _registerRemoteIdentity(Map<String, dynamic> event) {
    final senderAddress =
        event['senderAddress']?.toString().toLowerCase() ?? '';

    final deviceId = event['deviceId']?.toString().trim() ?? '';

    final contactName = event['name']?.toString().trim() ?? '';

    if (senderAddress.isEmpty ||
        deviceId.isEmpty ||
        contactName.isEmpty) {
      debugPrint('DisasterMesh: Invalid peer identity event');
      return;
    }

    final normalizedDeviceId = deviceId.toLowerCase();

    // Associate the Bluetooth address with the permanent app ID.
    _peerDeviceIds[senderAddress] = normalizedDeviceId;

    // Store the contact name using the permanent app ID.
    _contactNames[normalizedDeviceId] = contactName;

    debugPrint(
      'DisasterMesh: Peer identity registered: '
      '$contactName ($normalizedDeviceId)',
    );

    debugPrint(
      'DisasterMesh: Bluetooth address $senderAddress '
      'mapped to $normalizedDeviceId',
    );
  }

  static Future<void> start() async {
    if (_subscription != null) {
      debugPrint('DisasterMesh: Reception listener already active');
      return;
    }

    debugPrint('DisasterMesh: Starting message reception listener');

    _subscription = BleGattService.receivedMessageEvents.listen(
      (event) async {
        try {
          // Handle identity events separately from messages.
          if (event['eventType'] == 'peer_identity') {
            _registerRemoteIdentity(event);
            return;
          }

          final senderAddress =
              event['senderAddress']?.toString().toLowerCase() ?? '';

          final message = event['message']?.toString() ?? '';

          if (senderAddress.isEmpty || message.isEmpty) {
            debugPrint('DisasterMesh: Invalid incoming message');
            return;
          }

          // Resolve the sender's permanent DisasterMesh ID.
          final senderDeviceId = _peerDeviceIds[senderAddress];

          // Use permanent ID whenever identity is available.
          final conversationId =
              senderDeviceId ?? _activePeerId ?? senderAddress;

          final contactName =
              _contactNames[conversationId] ?? 'Nearby device';

          debugPrint(
            'DisasterMesh: Incoming sender: $senderAddress',
          );

          debugPrint(
            'DisasterMesh: Resolved device ID: '
            '${senderDeviceId ?? 'Not registered'}',
          );

          debugPrint(
            'DisasterMesh: Saving under: $conversationId',
          );

          // Save the incoming message first.
          // Native Android handles message notifications.
          await MessageStorageService.saveMessage(
            conversationId: conversationId,
            contactName: contactName,
            senderId: senderDeviceId ?? senderAddress,
            senderName: contactName,
            text: message,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isMe: false,
          );

          debugPrint(
            'DisasterMesh: Incoming message saved successfully',
          );
        } catch (e, stackTrace) {
          debugPrint('DisasterMesh: Message reception error: $e');
          debugPrintStack(stackTrace: stackTrace);
        }
      },
      onError: (error) {
        debugPrint('DisasterMesh: BLE message stream error: $error');
      },
      onDone: () {
        debugPrint('DisasterMesh: Message reception stream closed');
        _subscription = null;
      },
    );
  }

  static Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    debugPrint('DisasterMesh: Reception listener stopped');
  }
}
