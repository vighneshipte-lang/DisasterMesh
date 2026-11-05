import 'package:audioplayers/audioplayers.dart';

class EmergencyWhistleService {
  static final AudioPlayer _player = AudioPlayer();

  static bool _isPlaying = false;

  static bool get isPlaying => _isPlaying;

  static Future<void> startWhistle() async {
    if (_isPlaying) return;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);

      _isPlaying = true;

      await _player.play(AssetSource('audio/emergency_whistle.mp3'));
    } catch (e) {
      _isPlaying = false;
      rethrow;
    }
  }

  static Future<void> stopWhistle() async {
    try {
      await _player.stop();
    } finally {
      _isPlaying = false;
    }
  }

  static Future<void> dispose() async {
    await _player.dispose();
    _isPlaying = false;
  }
}
