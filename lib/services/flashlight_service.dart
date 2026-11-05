
import 'package:torch_light/torch_light.dart';

class FlashlightService {
  static Future<bool> turnOn() async {
    try {
      await TorchLight.enableTorch();
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> turnOff() async {
    try {
      await TorchLight.disableTorch();
      return true;
    } catch (e) {
      return false;
    }
  }
}
