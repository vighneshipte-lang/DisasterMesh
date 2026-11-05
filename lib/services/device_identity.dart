
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static const String _deviceIdKey = 'disaster_mesh_device_id';

  static Future<String> getDeviceId() async {
    final preferences = await SharedPreferences.getInstance();

    String? deviceId = preferences.getString(_deviceIdKey);

    if (deviceId == null) {
      deviceId = const Uuid().v4();

      await preferences.setString(
        _deviceIdKey,
        deviceId,
      );
    }

    return deviceId;
  }
}
