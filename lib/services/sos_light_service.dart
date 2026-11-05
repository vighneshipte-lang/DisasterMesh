
import 'dart:async';
import 'package:torch_light/torch_light.dart';

class SosLightService {
  static bool _isRunning = false;

  static bool get isRunning => _isRunning;

  /// Starts the repeating SOS Morse-code flashlight pattern.
  static Future<void> startSOS() async {
    if (_isRunning) return;

    _isRunning = true;

    try {
      while (_isRunning) {
        // S: Three short flashes
        for (int i = 0; i < 3 && _isRunning; i++) {
          await _flash(200);
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (!_isRunning) break;
        await Future.delayed(const Duration(milliseconds: 300));

        // O: Three long flashes
        for (int i = 0; i < 3 && _isRunning; i++) {
          await _flash(600);
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (!_isRunning) break;
        await Future.delayed(const Duration(milliseconds: 300));

        // S: Three short flashes
        for (int i = 0; i < 3 && _isRunning; i++) {
          await _flash(200);
          await Future.delayed(const Duration(milliseconds: 200));
        }

        await Future.delayed(const Duration(milliseconds: 1000));
      }
    } catch (e) {
      // Stop safely if the device cannot control its torch.
    } finally {
      _isRunning = false;
      await _turnTorchOff();
    }
  }

  static Future<void> _flash(int durationMs) async {
    if (!_isRunning) return;

    await TorchLight.enableTorch();
    await Future.delayed(Duration(milliseconds: durationMs));
    await _turnTorchOff();
  }

  /// Stops the SOS signal.
  static Future<void> stopSOS() async {
    _isRunning = false;
    await _turnTorchOff();
  }

  static Future<void> _turnTorchOff() async {
    try {
      await TorchLight.disableTorch();
    } catch (e) {
      // Torch may already be off or unavailable.
    }
  }
}
