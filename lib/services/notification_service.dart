
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
    'disaster_mesh_messages',
    'Chat Messages',
    description: 'Notifications for incoming DisasterMesh messages',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _connectionChannel =
      AndroidNotificationChannel(
    'disaster_mesh_connections',
    'Nearby Connections',
    description: 'Notifications when another DisasterMesh user connects',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(initializationSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_messageChannel);
    await androidPlugin?.createNotificationChannel(_connectionChannel);

    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  static Future<void> showMessageNotification({
    required String senderName,
    required String message,
    String? conversationId,
  }) async {
    if (!_initialized) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _messageChannel.id,
        _messageChannel.name,
        channelDescription: _messageChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      senderName,
      message,
      details,
      payload: conversationId,
    );
  }

  static Future<void> showConnectionNotification({
    required String deviceName,
  }) async {
    if (!_initialized) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _connectionChannel.id,
        _connectionChannel.name,
        channelDescription: _connectionChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      'New DisasterMesh Connection',
      '$deviceName connected to your device.',
      details,
    );
  }
}
