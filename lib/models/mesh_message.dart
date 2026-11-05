
import 'dart:convert';

class MeshMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String destinationId;
  final String text;
  final int hopLimit;
  final String type;
  final int timestamp;

  const MeshMessage({
    required this.id,
    required this.senderId,
    this.senderName = '',
    required this.destinationId,
    required this.text,
    this.hopLimit = 5,
    this.type = 'message',
    required this.timestamp,
  });

  // Convert message into JSON for BLE transmission.
  String toJson() {
    return jsonEncode({
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'destinationId': destinationId,
      'text': text,
      'hopLimit': hopLimit,
      'type': type,
      'timestamp': timestamp,
    });
  }

  // Reconstruct a message received through BLE.
  factory MeshMessage.fromJson(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);

    return MeshMessage(
      id: data['id'] as String,
      senderId: data['senderId'] as String,
      senderName: data['senderName'] as String? ?? '',
      destinationId: data['destinationId'] as String,
      text: data['text'] as String,
      hopLimit: data['hopLimit'] as int? ?? 5,
      type: data['type'] as String? ?? 'message',
      timestamp: data['timestamp'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  MeshMessage forward() {
    return MeshMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      destinationId: destinationId,
      text: text,
      hopLimit: hopLimit - 1,
      type: type,
      timestamp: timestamp,
    );
  }
}
