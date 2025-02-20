import 'package:alarm/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/home/home_controller.dart';
import '../drawer/drawer.dart';
import 'components/alarm_info_section.dart';
import 'components/analogue_clock.dart';
import 'components/custom_navigation_bar.dart';


class HomeScreen extends StatelessWidget {
  final controller = Get.put(HomeController());

  HomeScreen({super.key});


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            CustomNavigationBar(
              onMenuTap: () => controller.openDrawer(context),
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
                      Obx(() => AlarmInfoSection(
                        alarmTime: '12:06',
                        wakeUpIn: controller.wakeUpTime.value,
                        onEditAlarms: () => Get.toNamed(AppConstants.alarmHistory),
                        onAddAlarm: () => Get.toNamed(AppConstants.setAlarm),
                        addButtonAnimation: controller.addButtonAnimation,
                      )),
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