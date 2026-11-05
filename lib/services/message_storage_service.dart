
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class MessageStorageService {
  static const String _storageKey = 'disaster_mesh_messages';
  static final ValueNotifier<int> updates = ValueNotifier<int>(0);

  // Retrieve all saved messages.
  static Future<List<Map<String, dynamic>>> getAllMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final storedData = prefs.getString(_storageKey);

    if (storedData == null || storedData.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(storedData);
      return decoded
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Save a message.
  static Future<void> saveMessage({
    required String conversationId,
    required String contactName,
    required String senderId,
    required String senderName,
    required String text,
    required int timestamp,
    required bool isMe,
  }) async {
    final messages = await getAllMessages();

    messages.add({
      'conversationId': conversationId,
      'contactName': contactName,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': timestamp,
      'isMe': isMe,
      'isRead': isMe,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(messages));
    updates.value++;
  }

  // Retrieve messages belonging to one conversation.
  static Future<List<Map<String, dynamic>>> getConversationMessages(
    String conversationId,
  ) async {
    final messages = await getAllMessages();

    return messages.where((message) {
      return message['conversationId'] == conversationId;
    }).toList();
  }

  // Delete all saved messages.
  static Future<void> clearAllMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    updates.value++;
  }
}
