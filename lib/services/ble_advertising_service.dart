
import 'package:flutter/services.dart';

class BleAdvertisingService {
  static const MethodChannel _channel =
      MethodChannel('disaster_mesh/ble_advertising');

  static Future<bool> startAdvertising() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'startAdvertising',
      );

      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception(
        'Advertising failed: ${e.message ?? e.code}',
      );
    }
  }

  static Future<bool> stopAdvertising() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'stopAdvertising',
      );

      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception(
        'Unable to stop advertising: ${e.message ?? e.code}',
      );
    }
  }
}
