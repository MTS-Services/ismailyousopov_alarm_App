import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/alarm/alarm_model.dart';
import '../../views/home/components/alarm_info_section.dart';
import 'dart:async';
import '../alarm/alarm_controller.dart';

class HomeController extends GetxController
    with AlarmAnimationController, GetTickerProviderStateMixin {
  static HomeController get instance => Get.find<HomeController>();

  late final GlobalKey<ScaffoldState> scaffoldKey;
  final Rx<DateTime> currentTime = DateTime.now().obs;
  final RxString wakeUpTime = ''.obs;
  Timer? _clockTimer;

  @override
  void onInit() {
    scaffoldKey = GlobalKey<ScaffoldState>();
    super.onInit();
    initializeAnimations(this);
    addButtonController.forward();
    _startClockTimer();
    updateWakeUpTime();
  }

  /// Cleanup resources when controller is no longer needed
  @override
  void onClose() {
    _clockTimer?.cancel();
    disposeAnimations();
    super.onClose();
  }

  /// Starts a timer to update current time every second
  void _startClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      currentTime.value = DateTime.now();
    });
  }

  /// Opens the app drawer
  void openDrawer(BuildContext context) {
    final scaffoldState = Scaffold.of(context);
    if (scaffoldState.hasDrawer && !scaffoldState.isDrawerOpen) {
      scaffoldState.openDrawer();
    }
  }

  /// Updates the wake-up time text based on next alarm
  void updateWakeUpTime() {
    final alarmController = Get.find<AlarmController>();
    final nextAlarm = _getNextActiveAlarm(alarmController);

    if (nextAlarm == null) {
      wakeUpTime.value = 'No alarm set';
      return;
    }

    final now = DateTime.now();
    final nextAlarmTime = nextAlarm.getNextAlarmTime();
    final difference = nextAlarmTime.difference(now);
    if (difference.inHours >= 24) {
      final days = difference.inDays;
      wakeUpTime.value = 'Wake up in $days day${days > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      wakeUpTime.value = 'Wake up in ${hours}h ${minutes}m';
    } else if (difference.inMinutes > 0) {
      wakeUpTime.value = 'Wake up in ${difference.inMinutes}m';
    } else {
      wakeUpTime.value = 'Alarm is now!';
    }
  }

  /// Gets the next active alarm to trigger
  AlarmModel? _getNextActiveAlarm(AlarmController alarmController) {
    final activeAlarms = alarmController.getActiveAlarms();
    if (activeAlarms.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    AlarmModel? nextAlarm;
    DateTime? earliestTime;

    for (final alarm in activeAlarms) {
      final nextTriggerTime = alarm.getNextAlarmTime();
      if (nextTriggerTime.isBefore(now) && !alarm.isRepeating) {
        continue;
      }

      if (earliestTime == null || nextTriggerTime.isBefore(earliestTime)) {
        earliestTime = nextTriggerTime;
        nextAlarm = alarm;
      }
    }

    return nextAlarm;
  }
}
