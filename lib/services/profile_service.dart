
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ProfileService {
  static const String _displayNameKey = 'display_name';
  static const String _deviceIdKey = 'disaster_mesh_device_id';
  static const String _privacyKey = 'privacy_setting';
  static const String _notificationsKey = 'notifications_enabled';

  static const Uuid _uuid = Uuid();

  // Get the user's display name.
  static Future<String?> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_displayNameKey);

    if (name == null || name.trim().isEmpty) {
      return null;
    }

    return name.trim();
  }

  // Save the user's display name.
  static Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name.trim());
  }

  // Get the permanent device ID.
  // Generate one only when this installation does not have one.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'DM-${_uuid.v4().replaceAll('-', '').toUpperCase()}';
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  // Get the user's privacy setting.
  static Future<String> getPrivacySetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_privacyKey) ?? 'Requests only';
  }

  // Get notification preference.
  static Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsKey) ?? true;
  }
}
