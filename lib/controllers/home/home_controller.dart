import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../views/home/components/alarm_info_section.dart';

class HomeController extends GetxController with AlarmAnimationController, GetSingleTickerProviderStateMixin {
  static HomeController get instance => Get.find<HomeController>();
  late final GlobalKey<ScaffoldState> scaffoldKey;
  final Rx<DateTime> currentTime = DateTime.now().obs;
  final RxString wakeUpTime = ''.obs;

  @override
  void onInit() {
    scaffoldKey = GlobalKey<ScaffoldState>();
    super.onInit();
    initializeAnimations(this);
    addButtonController.forward();
    updateWakeUpTime();
  }

  void openDrawer(BuildContext context) {
    Scaffold.of(context).openDrawer();
  }

  void updateWakeUpTime() {
    final now = DateTime.now();
    final alarmTime = DateTime(now.year, now.month, now.day, 12, 06);
    final difference = alarmTime.difference(now);

    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    wakeUpTime.value = 'Wake up in ${hours}h ${minutes}m';
  }
}