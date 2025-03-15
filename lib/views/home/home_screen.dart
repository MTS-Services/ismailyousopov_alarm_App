import 'package:alarm/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/home/home_controller.dart';
import '../../controllers/alarm/alarm_controller.dart';
import '../../models/alarm/alarm_model.dart';
import '../drawer/drawer.dart';
import 'components/alarm_info_section.dart';
import 'components/analogue_clock.dart';
import 'components/custom_navigation_bar.dart';
import 'dart:async';

/// Main screen displaying current time and next alarm information
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final alarmController = Get.put(AlarmController());
  final homeController = Get.put(HomeController());

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      alarmController.loadAlarms();
      _setupPeriodicRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Sets up a periodic timer to refresh alarm countdown information
  void _setupPeriodicRefresh() {
    _refreshTimer?.cancel();

    final now = DateTime.now();
    final secondsToNextMinute = 60 - now.second;

    Future.delayed(Duration(seconds: secondsToNextMinute), () {
      alarmController.refreshTimestamp.value =
          DateTime.now().millisecondsSinceEpoch;

      _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        alarmController.refreshTimestamp.value =
            DateTime.now().millisecondsSinceEpoch;
      });
    });
  }

  /// Gets the next active alarm time in formatted string (e.g., "8:30 AM")
  String _getNextAlarmTime() {
    final nextAlarm = _getNextActiveAlarm();
    if (nextAlarm == null) {
      return 'No Alarm';
    }

    return nextAlarm.getFormattedTime();
  }

  /// Calculates how much time is left until the next alarm
  String _calculateWakeUpTimeText() {
    final nextAlarm = _getNextActiveAlarm();
    if (nextAlarm == null) {
      return 'No alarm set';
    }

    final now = DateTime.now();
    final nextAlarmTime = nextAlarm.getNextAlarmTime();

    final difference = nextAlarmTime.difference(now);

    if (difference.inHours >= 24) {
      final days = difference.inDays;
      return 'Wake up in $days day${days > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      return 'Wake up in ${hours}h ${minutes}m';
    } else if (difference.inMinutes > 0) {
      return 'Wake up in ${difference.inMinutes}m';
    } else {
      return 'Alarm is now!';
    }
  }

  /// Checks if there are any active alarms
  bool _hasActiveAlarms() {
    return _getNextActiveAlarm() != null;
  }

  /// Gets the next active alarm to trigger
  AlarmModel? _getNextActiveAlarm() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            CustomNavigationBar(
              onMenuTap: () => homeController.openDrawer(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Clock Widget
                      const ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        child: AnalogClock(
                          size: 300,
                          backgroundColor: Colors.white,
                          numberColor: Colors.black,
                          handColor: Colors.black,
                          secondHandColor: Colors.red,
                        ),
                      ),
                      Obx(() {
                        final _ = alarmController.alarms.length;
                        final __ = alarmController.refreshTimestamp.value;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: _hasActiveAlarms() ? 40 : 60,
                        );
                      }),

                      Obx(() {
                        final _ = alarmController.alarms.length;
                        final __ = alarmController.refreshTimestamp.value;

                        final hasAlarms = _hasActiveAlarms();
                        return AlarmInfoSection(
                          alarmTime: hasAlarms ? _getNextAlarmTime() : "",
                          wakeUpIn: hasAlarms ? _calculateWakeUpTimeText() : "",
                          onEditAlarms: () =>
                              Get.toNamed(AppConstants.alarmEdit),
                          onAddAlarm: () => Get.toNamed(AppConstants.setAlarm),
                          addButtonAnimation: homeController.addButtonAnimation,
                          hasActiveAlarms: hasAlarms,
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
