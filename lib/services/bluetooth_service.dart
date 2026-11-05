
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  static Future<String> getBluetoothStatus() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;

      if (!isSupported) {
        return 'Bluetooth is not supported on this device.';
      }

      final state = await FlutterBluePlus.adapterState
          .firstWhere(
            (state) => state != BluetoothAdapterState.unknown,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => BluetoothAdapterState.unknown,
          );

      switch (state) {
        case BluetoothAdapterState.on:
          return 'Bluetooth is ON and ready.';

        case BluetoothAdapterState.off:
          return 'Bluetooth is OFF. Please turn it on.';

        case BluetoothAdapterState.unauthorized:
          return 'Bluetooth permission is not authorized.';

        case BluetoothAdapterState.unavailable:
          return 'Bluetooth is unavailable on this device.';

        default:
          return 'Unable to determine Bluetooth status. Please try again.';
      }
    } catch (e) {
      return 'Unable to check Bluetooth status: $e';
    }
  }
}
