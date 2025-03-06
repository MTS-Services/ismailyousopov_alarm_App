import 'package:alarm/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/home/home_controller.dart';
import '../../controllers/alarm/alarm_controller.dart';
import '../drawer/drawer.dart';
import 'components/alarm_info_section.dart';
import 'components/analogue_clock.dart';
import 'components/custom_navigation_bar.dart';

class HomeScreen extends StatelessWidget {
  final homeController = Get.put(HomeController());
  final alarmController = Get.put(AlarmController());

  HomeScreen({super.key});

  String _getNextAlarmTime() {
    final activeAlarms = alarmController.getActiveAlarms();
    if (activeAlarms.isEmpty) {
      return 'No Alarm';
    }

    final now = DateTime.now();

    final validAlarms = activeAlarms.where((alarm) =>
    alarm.time.isAfter(now) || alarm.isRepeating
    ).toList();

    if (validAlarms.isEmpty) {
      return 'No Alarm';
    }

    // Sort by time
    validAlarms.sort((a, b) => a.time.compareTo(b.time));


    DateTime? nextOccurrenceTime;
    for (final alarm in validAlarms) {
      DateTime alarmTime = alarm.time;


      if (alarmTime.isBefore(now) && alarm.isRepeating) {
        while (alarmTime.isBefore(now)) {
          alarmTime = alarmTime.add(const Duration(days: 1));
        }
      } else if (alarmTime.isBefore(now)) {
        continue;
      }


      if (nextOccurrenceTime == null || alarmTime.isBefore(nextOccurrenceTime)) {
        nextOccurrenceTime = alarmTime;
      }
    }


    if (nextOccurrenceTime == null) {
      return 'No Alarm';
    }


    final hour = nextOccurrenceTime.hour;
    final minute = nextOccurrenceTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    return '$formattedHour:$minute $period';
  }

  String _calculateWakeUpTimeText() {
    final activeAlarms = alarmController.getActiveAlarms();
    if (activeAlarms.isEmpty) {
      return 'No alarm set';
    }


    activeAlarms.sort((a, b) => a.time.compareTo(b.time));

    final now = DateTime.now();
    final futureAlarms = activeAlarms.where((alarm) => alarm.time.isAfter(now)).toList();


    if (futureAlarms.isEmpty) {

      final repeatingAlarms = activeAlarms.where((alarm) => alarm.isRepeating).toList();
      if (repeatingAlarms.isEmpty) {
        return 'No alarm set';
      }


      repeatingAlarms.sort((a, b) => a.time.compareTo(b.time));
      DateTime nextOccurrence = repeatingAlarms.first.time;

      while (nextOccurrence.isBefore(now)) {
        nextOccurrence = nextOccurrence.add(const Duration(days: 1));
      }

      final difference = nextOccurrence.difference(now);
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;

      return 'Wake up in ${hours}h ${minutes}m';
    }

    final nextAlarm = futureAlarms.first;
    final difference = nextAlarm.time.difference(now);

    // Format the time difference
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      const Visibility(
                        visible: true,
                        child: ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          child: AnalogClock(
                            size: 300,
                            backgroundColor: Colors.white,
                            numberColor: Colors.black,
                            handColor: Colors.black,
                            secondHandColor: Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Obx(() {
                        alarmController.alarms;

                        return AlarmInfoSection(
                          alarmTime: _getNextAlarmTime(),
                          wakeUpIn: _calculateWakeUpTimeText(),
                          onEditAlarms: () => Get.toNamed(AppConstants.alarmHistory),
                          onAddAlarm: () => Get.toNamed(AppConstants.setAlarm),
                          addButtonAnimation: homeController.addButtonAnimation,
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