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
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/background_service.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await alarmController.loadAlarms();
      _setupPeriodicRefresh();
      await _checkForActiveAlarm();
      await _checkAlarmLaunchIntent();
      
      // Add a listener to detect active alarms while the app is open
      _setupActiveAlarmListener();
    });
  }

  /// Checks if the app was launched from an alarm notification
  Future<void> _checkAlarmLaunchIntent() async {
    try {
      final launchData = await AlarmBackgroundService.getAlarmLaunchData();
      if (launchData != null && launchData['fromAlarm'] == true) {
        final int alarmId = launchData['alarmId'] ?? 0;
        final int soundId = launchData['soundId'] ?? 1;
        final bool directToStop = launchData['directToStop'] ?? false;
        
        debugPrint('App launched with alarm data: alarmId=$alarmId, directToStop=$directToStop');
        
        if (alarmId > 0) {
          // Handle direct stop button case - go straight to stop screen without starting alarm
          if (directToStop) {
            // Clear the directToStop flag after handling it
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('flutter.direct_to_stop');
            
            _navigateToStopAlarmScreen(alarmId, soundId);
          } else {
            // Normal case: start the alarm and then navigate to stop screen
            await AlarmBackgroundService.forceStartAlarmIfNeeded(alarmId, soundId);
            _navigateToStopAlarmScreen(alarmId, soundId);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking alarm launch intent: $e');
    }
  }
  
  /// Checks if there's an active alarm that requires the stop screen
  Future<void> _checkForActiveAlarm() async {
    try {
      final isActive = await AlarmBackgroundService.isAlarmActive();
      if (isActive) {
        final prefs = await SharedPreferences.getInstance();
        final activeAlarmId = prefs.getInt('flutter.active_alarm_id');
        final activeSoundId = prefs.getInt('flutter.active_alarm_sound') ?? 1;
        
        if (activeAlarmId != null && activeAlarmId > 0) {
          // Check if we're already on the stop alarm screen or NFC scan screen
          final currentRoute = Get.currentRoute;
          final isOnStopScreen = currentRoute.contains(AppConstants.stopAlarm);
          final isOnNfcScreen = currentRoute.contains(AppConstants.nfcScan);
          
          if (!isOnStopScreen && !isOnNfcScreen) {
            _navigateToStopAlarmScreen(activeAlarmId, activeSoundId);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for active alarm: $e');
    }
  }
  
  /// Navigates to the appropriate stop alarm screen
  void _navigateToStopAlarmScreen(int alarmId, int soundId) {
    // Always navigate to the stop alarm screen, regardless of NFC requirement
    Get.offNamed(
      AppConstants.stopAlarm,
      arguments: {'alarmId': alarmId, 'soundId': soundId},
    );
  }

  /// Sets up a listener to detect when an alarm becomes active while the app is open
  void _setupActiveAlarmListener() {
    // Use GetX's observables instead of a regular listener
    ever(alarmController.hasActiveAlarm, (isActive) async {
      if (isActive) {
        final prefs = await SharedPreferences.getInstance();
        final activeAlarmId = prefs.getInt('flutter.active_alarm_id');
        final activeSoundId = prefs.getInt('flutter.active_alarm_sound') ?? 1;
        
        if (activeAlarmId != null && activeAlarmId > 0) {
          // Only navigate if we're not already on the stop alarm screen
          if (!Get.currentRoute.contains(AppConstants.stopAlarm) && 
              !Get.currentRoute.contains(AppConstants.nfcScan)) {
            _navigateToStopAlarmScreen(activeAlarmId, activeSoundId);
          }
        }
      }
    });
    
    // Add a listener for the shouldShowStopScreen value
    ever(alarmController.shouldShowStopScreen, (shouldShow) async {
      if (shouldShow) {
        final activeAlarmId = alarmController.activeAlarmId.value;
        final prefs = await SharedPreferences.getInstance();
        final activeSoundId = prefs.getInt('flutter.active_alarm_sound') ?? 1;
        
        if (activeAlarmId > 0) {
          // Only navigate if we're not already on the stop alarm screen
          if (!Get.currentRoute.contains(AppConstants.stopAlarm) && 
              !Get.currentRoute.contains(AppConstants.nfcScan)) {
            _navigateToStopAlarmScreen(activeAlarmId, activeSoundId);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    // No need to remove listeners with GetX's reactive approach
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
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 15,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(150)),
                          child: AnalogClock(
                            size: 300,
                            backgroundColor: Colors.white,
                            numberColor: Colors.black,
                            handColor: Colors.black,
                            secondHandColor: Colors.red,
                          ),
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
