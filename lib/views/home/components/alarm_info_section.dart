import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class AlarmInfoSection extends StatelessWidget {
  final String alarmTime;
  final String wakeUpIn;
  final VoidCallback onEditAlarms;
  final VoidCallback onAddAlarm;
  final Animation<double>? addButtonAnimation;
  final bool hasActiveAlarms;

  const AlarmInfoSection({
    super.key,
    required this.alarmTime,
    required this.wakeUpIn,
    required this.onEditAlarms,
    required this.onAddAlarm,
    this.addButtonAnimation,
    this.hasActiveAlarms = false,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAlarmInfoDisplay(context, primaryColor),
        const SizedBox(height: 16),
        _buildEditAlarmsButton(context, textColor),
        const SizedBox(height: 16),
        _buildAddAlarmButton(context, primaryColor),
      ],
    );
  }

  /// Builds the alarm time and wake up time display section
  Widget _buildAlarmInfoDisplay(BuildContext context, Color primaryColor) {
    if (hasActiveAlarms) {
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
              color: primaryColor,
              letterSpacing: 0.0,
            ),
          ),
        ],
      );
    } else {
      return Text(
        'No Active Alarm!',
        style: TextStyle(
          color: primaryColor,
          fontSize: 14,
        ),
      );
    }
  }

  /// Builds the edit alarms button
  Widget _buildEditAlarmsButton(BuildContext context, Color textColor) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      height: 56,
      child: ElevatedButton(
        onPressed: onEditAlarms,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: textColor),
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
    );
  }

  /// Builds the add alarm floating action button with animation
  Widget _buildAddAlarmButton(BuildContext context, Color primaryColor) {
    if (addButtonAnimation != null) {
      return _buildAddButton(context, primaryColor);
    } else {
      return _buildAddButton(context, primaryColor);
    }
  }

  /// Helper method to build the actual add button
  Widget _buildAddButton(BuildContext context, Color primaryColor) {
    return Align(
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
            color: primaryColor,
            borderRadius: BorderRadius.circular(28),
          ),
          child: InkWell(
            splashColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: onAddAlarm,
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mixin to handle animations related to alarm UI components
mixin AlarmAnimationController on GetxController {
  late AnimationController addButtonController;
  late Animation<double> addButtonAnimation;
  AnimationController? _rippleController;
  Animation<double>? _rippleAnimation;

  /// Initializes all animation controllers and animations
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

    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: vsync,
    );

    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _rippleController!,
        curve: Curves.easeOut,
      ),
    );
  }

  /// Plays the add button entrance animation
  void playAddButtonAnimation() {
    if (!addButtonController.isAnimating &&
        addButtonController.status != AnimationStatus.completed) {
      addButtonController.forward();
    }
  }

  /// Plays a ripple animation to highlight an alarm is triggering
  void playRippleAnimation({bool repeat = true}) {
    if (_rippleController == null) return;

    if (repeat) {
      _rippleController!.repeat();
    } else {
      _rippleController!.forward();
    }
  }

  /// Stops any ongoing ripple animation
  void stopRippleAnimation() {
    if (_rippleController == null) return;

    if (_rippleController!.isAnimating) {
      _rippleController!.stop();
      _rippleController!.reset();
    }
  }

  /// Gets the ripple animation for use in UI components
  Animation<double>? get rippleAnimation => _rippleAnimation;

  /// Properly disposes all animation controllers
  void disposeAnimations() {
    addButtonController.dispose();
    _rippleController?.dispose();
  }

  @override
  void onClose() {
    disposeAnimations();
    super.onClose();
  }
}
