import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class VolumeLockManager {
  double _fixedVolume = 1.0;
  bool _isListening = false;

  void startLockingVolume({double volume = 1.0}) async {
    _fixedVolume = volume;

    // Set fixed volume initially
    await FlutterVolumeController.setVolume(_fixedVolume);

    if (!_isListening) {
      FlutterVolumeController.addListener((double current) async {
        // যদি user volume button চেপে volume change করে:
        if ((current - _fixedVolume).abs() > 0.01) {
          await FlutterVolumeController.setVolume(_fixedVolume);
        }
      });
      _isListening = true;
    }
  }

  void stopLockingVolume() {
    if (_isListening) {
      FlutterVolumeController.removeListener();
      _isListening = false;
    }
  }
}
