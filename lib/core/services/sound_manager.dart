
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class SoundManager {
  static const Map<int, String> soundPaths = {
    1: 'alarm_sounds/sound_1.wav',
    2: 'alarm_sounds/sound_2.wav',
    3: 'alarm_sounds/sound_3.wav',
    4: 'alarm_sounds/sound_4.wav',
    5: 'alarm_sounds/sound_5.wav',
    6: 'alarm_sounds/sound_6.wav',
    7: 'alarm_sounds/sound_7.wav',
    8: 'alarm_sounds/sound_8.wav',
  };

  /// Sound names for ui
  static const Map<int, String> soundNames = {
    1: 'Classic Alarm',
    2: 'Soft Chimes',
    3: 'Digital Beep',
    4: 'Nature Wake',
    5: 'Urgent Alert',
    6: 'Deep Bass',
    7: 'Gentle Rise',
    8: 'Morning Melody',
  };

  /// Returns the asset path for in-app audio playback via assets
  static String getSoundPath(int soundId) {
    return 'alarm_sounds/sound_${soundId}.wav';
  }


  /// Returns the name for a given sound ID
  static String getSoundName(int soundId) {
    return soundNames[soundId] ?? 'Default Sound';
  }

  /// Returns the notification sound name for Android (without extension)
  static String getNotificationSoundName(int soundId) {
    return 'sound_$soundId';
  }
  /// Returns the notification sound file name for iOS (with extension)
  static String getIOSNotificationSound(int soundId) {
    return 'sound_$soundId.wav';
  }
  /// Returns the total count of available sounds
  static int soundCount() {
    return soundPaths.length;
  }

  /// Returns a list of all available sounds
  static List<Map<String, dynamic>> getAllSounds() {
    return List.generate(soundPaths.length, (index) {
      final id = index + 1;
      return {
        'id': id,
        'name': getSoundName(id),
        'path': getSoundPath(id),
      };
    });
  }

  /// Preloads all sound assets for in-app playback to reduce delay
  static Future<void> preloadAllSounds(AudioPlayer player) async {
    try {
      for (final id in soundPaths.keys) {
        final path = getSoundPath(id);
        await player.setSourceAsset(path);
      }
    } catch (e) {
      debugPrint('Error preloading sounds: $e');
    }
  }

  /// Debug function to verify sound configurations
  static void debugSoundConfiguration(int soundId) {
    debugPrint('=== SOUND CONFIGURATION DEBUG ===');
    debugPrint('Sound ID: $soundId');
    debugPrint('Sound Name: ${getSoundName(soundId)}');
    debugPrint('In-app Asset Path: ${getSoundPath(soundId)}');
    debugPrint('Android Notification Sound: ${getNotificationSoundName(soundId)}');
    debugPrint('iOS Notification Sound: ${getIOSNotificationSound(soundId)}');
  }
}