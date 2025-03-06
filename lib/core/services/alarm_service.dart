import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class PersistentAlarmService {
  static final PersistentAlarmService _singleton = PersistentAlarmService._internal();
  factory PersistentAlarmService() => _singleton;

  PersistentAlarmService._internal();

  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;

  Future<void> startAlarmSound(String soundPath, {double volume = 1.0}) async {
    // Stop any existing sound
    await stopAlarmSound();

    try {
      // Initialize new audio player
      _audioPlayer = AudioPlayer();

      // Set loop mode
      await _audioPlayer?.setReleaseMode(ReleaseMode.loop);

      // Set volume (0.0 to 1.0)
      await _audioPlayer?.setVolume(volume);

      // Play sound from assets
      await _audioPlayer?.play(AssetSource(soundPath));

      _isPlaying = true;
      debugPrint('Persistent Alarm Sound Started');
    } catch (e) {
      debugPrint('Error starting persistent alarm sound: $e');
    }
  }

  Future<void> stopAlarmSound() async {
    if (_audioPlayer != null) {
      await _audioPlayer?.stop();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      _isPlaying = false;
      debugPrint('Persistent Alarm Sound Stopped');
    }
  }

  bool get isPlaying => _isPlaying;
}