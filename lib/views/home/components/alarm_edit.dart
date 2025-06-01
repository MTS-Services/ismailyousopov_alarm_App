import 'dart:io';

import 'package:alarmapp/views/home/components/alarm_history.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../controllers/alarm/alarm_controller.dart';
import '../../../core/constants/asset_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/alarm/alarm_model.dart';
import '../../../core/services/notification_service.dart';

class AlarmEditScreen extends StatefulWidget {
  const AlarmEditScreen({super.key});

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final AlarmController _alarmController = Get.put(AlarmController());
  List<AlarmModel> _alarms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  /// Loads all active alarms from the database (enabled and future alarms)
  Future<void> _loadAlarms() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allAlarms = await _databaseHelper.getAllAlarms();

      final activeAlarms = allAlarms.where((alarm) {
        if (!alarm.isEnabled) return false;

        final now = DateTime.now();
        if (alarm.daysActive.isEmpty || alarm.daysActive.first.isEmpty) {
          return alarm.time.isAfter(now);
        }

        return true;
      }).toList();

      setState(() {
        _alarms = activeAlarms;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading alarms: $e');
      setState(() {
        _isLoading = false;
      });
      _showFeedbackMessage('Error loading alarms', isError: true);
    }
  }

  /// Disables an alarm and cancels its notification
  Future<void> _cancelAlarm(AlarmModel alarm) async {
    if (alarm.id == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final activeAlarmId = prefs.getInt('flutter.active_alarm_id');

      if (activeAlarmId == alarm.id) {
        await _alarmController.stopAlarm(alarm.id!);

        try {
          await const MethodChannel('com.example.alarm/background_channel')
              .invokeMethod('forceStopService');
        } catch (e) {
          debugPrint('Error stopping native service: $e');
        }
      }

      // Use the updated cancelAlarm method that uses the Alarm package
      await _alarmController.cancelAlarm(alarm);

      await _alarmController.loadAlarms();

      _showFeedbackMessage('Alarm canceled successfully');
      _loadAlarms();
    } catch (e) {
      debugPrint('Error canceling alarm: $e');
      _showFeedbackMessage('Failed to cancel alarm', isError: true);
    }
  }

  /// Navigates to the alarm settings screen with the selected alarm for editing
  void _editAlarm(AlarmModel alarm) {
    _alarmController.stopAlarmSound();
    Get.toNamed(
      AppConstants.setAlarm,
      arguments: alarm,
    )?.then((_) {
      _alarmController.forceRefreshUI();
      _loadAlarms();
    });
  }

  /// Displays a time widget with hours and minutes in 24-hour format
  Widget _formatTimeWidget(DateTime? time, {double scaleFactor = 1.0}) {
    if (time == null) return const Text('');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final timeFontSize = 35.0 * scaleFactor;

    return Text(
      '$hour:$minute',
      style: GoogleFonts.interTight(
        color: Colors.white,
        fontSize: timeFontSize,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// Shows visual indicators for which days of the week the alarm is active
  Widget _buildDaysIndicator(AlarmModel alarm, {double scaleFactor = 1.0}) {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final circleSize = 22.0 * scaleFactor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (index) {
        final isActive = alarm.daysActive.contains((index + 1).toString());
        return Container(
          width: circleSize,
          height: circleSize,
          margin: EdgeInsets.symmetric(horizontal: 2 * scaleFactor),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
          ),
          child: Center(
            child: Text(
              dayLabels[index],
              style: TextStyle(
                fontSize: 10 * scaleFactor,
                fontWeight: FontWeight.bold,
                color: isActive ? Theme.of(context).primaryColor : Colors.white,
              ),
            ),
          ),
        );
      }),
    );
  }

  /// Shows a feedback message to the user
  void _showFeedbackMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: Theme.of(context).textTheme.bodyLarge?.color,
              size: 35,
            ),
            onPressed: () => Get.toNamed(AppConstants.home),
          ),
          title: Text(
            'Edit Alarms',
            style: GoogleFonts.interTight(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          titleSpacing: 0,
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildBodyContent(),
          ),
        ),
      ),
    );
  }

  /// Builds the main content based on loading state and alarm availability
  Widget _buildBodyContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_alarms.isEmpty) {
      return Center(
        child: Text(
          'No active alarms found',
          style: GoogleFonts.interTight(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          for (var alarm in _alarms) _buildAlarmCard(alarm),
        ].divide(const SizedBox(height: 16)),
      ),
    );
  }

  /// Builds an individual alarm card with time display, days indicator and action buttons
  Widget _buildAlarmCard(AlarmModel alarm) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth < 320
        ? 0.75
        : screenWidth < 360
            ? 0.85
            : screenWidth < 400
                ? 0.95
                : 1.0;

    return Material(
      color: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(16 * scaleFactor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Always use Row layout for consistent design across all devices
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 22 * scaleFactor),
                    child:
                        _formatTimeWidget(alarm.time, scaleFactor: scaleFactor),
                  ),
                  _buildActionButtons(alarm, scaleFactor: scaleFactor),
                ],
              ),
              if (alarm.daysActive.isNotEmpty &&
                  alarm.daysActive.first.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    left: 22 * scaleFactor,
                    top: 8 * scaleFactor,
                  ),
                  child: Center(
                    child: _buildDaysIndicator(alarm, scaleFactor: scaleFactor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds action buttons (Cancel and Edit)
  Widget _buildActionButtons(AlarmModel alarm, {double scaleFactor = 1.0}) {
    final buttonHeight = 36.0 * scaleFactor;
    final buttonWidth = max(70.0 * scaleFactor, 60.0);
    final fontSize = 14.0 * scaleFactor;
    final horizontalPadding = 8.0 * scaleFactor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: () => _cancelAlarm(alarm),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: horizontalPadding / 2,
            ),
            minimumSize: Size(buttonWidth, buttonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18 * scaleFactor),
            ),
            elevation: 0,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Inter',
                color: const Color(0xFFF9F8F8),
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
        SizedBox(width: 8 * scaleFactor),
        ElevatedButton(
          onPressed: () => _editAlarm(alarm),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: horizontalPadding / 2,
            ),
            minimumSize: Size(buttonWidth, buttonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18 * scaleFactor),
            ),
            elevation: 0,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Edit',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

double max(double a, double b) {
  return a > b ? a : b;
}
