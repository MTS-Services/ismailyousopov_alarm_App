import 'package:alarm/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class AlarmInfoSection extends StatelessWidget {
  final String alarmTime;
  final String wakeUpIn;
  final VoidCallback onEditAlarms;
  final VoidCallback onAddAlarm;
  final Animation<double>? addButtonAnimation;

  const AlarmInfoSection({
    super.key,
    required this.alarmTime,
    required this.wakeUpIn,
    required this.onEditAlarms,
    required this.onAddAlarm,
    this.addButtonAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Alarm set for',
          style: GoogleFonts.inter(
            letterSpacing: 0.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          alarmTime,
          style: GoogleFonts.interTight(
            fontSize: 35,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          wakeUpIn,
          style: GoogleFonts.inter(
            color: Theme.of(context).primaryColor,
            letterSpacing: 0.0,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: MediaQuery.of(context).size.width,
          height: 56,
          child: ElevatedButton(
            onPressed: onEditAlarms,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                ),
              ),
              padding: const EdgeInsets.all(8),
            ),
            child: Text(
              'Edit Alarms',
              style: GoogleFonts.interTight(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        Align(
          alignment: const AlignmentDirectional(0, 0),
          child: Material(
            color: Colors.transparent,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(28),
              ),
              child: InkWell(
                splashColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap:  () => Get.toNamed(AppConstants.setAlarm),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


mixin AlarmAnimationController on GetxController {
  late AnimationController addButtonController;
  late Animation<double> addButtonAnimation;

  void initializeAnimations(TickerProvider vsync) {
    addButtonController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: vsync,
    );

    addButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: addButtonController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void onClose() {
    addButtonController.dispose();
    super.onClose();
  }
}