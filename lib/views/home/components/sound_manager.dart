class SoundManager {
  static const Map<int, String> soundPaths = {
    1: 'alarm_sounds/1.wav',
    2: 'alarm_sounds/2.wav',
    3: 'alarm_sounds/3.wav',
    4: 'alarm_sounds/4.wav',
    5: 'alarm_sounds/5.wav',
    6: 'alarm_sounds/6.wav',
    7: 'alarm_sounds/7.wav',
    8: 'alarm_sounds/8.wav',
  };

  static String getSoundPath(int soundId) {
    return soundPaths[soundId] ?? soundPaths[1]!;
  }

  static String getSoundName(int soundId) {
    final names = {
      1: 'Classic Alarm',
      2: 'Soft Chimes',
      3: 'Digital Beep',
      4: 'Nature Wake',
      5: 'Urgent Alert',
      6: 'Deep Bass',
      7: 'Gentle Rise',
      8: 'Morning Melody',
    };
    return names[soundId] ?? 'Default Sound';
  }
}