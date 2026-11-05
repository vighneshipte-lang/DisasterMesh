import '../models/mesh_message.dart';

class MeshRouter {
  final Set<String> _seenMessageIds = {};

  bool receive(MeshMessage message) {
    if (message.hopLimit < 0) return false;

    if (_seenMessageIds.contains(message.id)) {
      return false;
    }

    _seenMessageIds.add(message.id);
    return true;
  }

  bool isMessageForDevice(MeshMessage message, String deviceId) {
    return message.destinationId == deviceId;
  }

  bool shouldForward(MeshMessage message, String deviceId) {
    return !isMessageForDevice(message, deviceId) && message.hopLimit > 0;
  }

  MeshMessage? prepareForward(MeshMessage message, String deviceId) {
    if (!shouldForward(message, deviceId)) {
      return null;
    }

    return message.forward();
  }

  List<String> simulateThreeDeviceRoute() {
    final logs = <String>[];

    final original = MeshMessage(
      id: 'SOS-001',
      senderId: 'A',
      destinationId: 'C',
      text: 'Emergency! Need assistance.',
      hopLimit: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final phoneB = MeshRouter();
    final phoneC = MeshRouter();

    logs.add('A creates a message for C.');

    final messageAtB = original.forward();

    if (phoneB.receive(messageAtB)) {
      logs.add('B receives and stores the message.');

      final messageAtC = messageAtB.forward();

      if (phoneC.receive(messageAtC)) {
        logs.add('C receives the message successfully.');
      } else {
        logs.add('C rejected the message.');
      }

      if (!phoneB.receive(messageAtB)) {
        logs.add('B rejects a duplicate message.');
      }
    }

    logs.add('Internet connection: not used.');

    return logs;
  }
}
