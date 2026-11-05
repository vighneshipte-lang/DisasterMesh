
import 'package:permission_handler/permission_handler.dart';

class BluetoothPermissionService {
  static Future<bool> requestPermissions() async {
    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();
    final advertiseStatus = await Permission.bluetoothAdvertise.request();

    // Android 11 and below only deliver BLE scan results when location
    // permission is granted (Android 12+ does not need it because of the
    // neverForLocation flag), so ask for it but do not fail if it is denied.
    await Permission.locationWhenInUse.request();

    return scanStatus.isGranted &&
        connectStatus.isGranted &&
        advertiseStatus.isGranted;
  }

  static Future<bool> arePermissionsGranted() async {
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    final advertiseStatus = await Permission.bluetoothAdvertise.status;

    return scanStatus.isGranted &&
        connectStatus.isGranted &&
        advertiseStatus.isGranted;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
