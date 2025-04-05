import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';

import '../../../controllers/alarm/alarm_controller.dart';
import '../../../core/constants/asset_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/alarm/alarm_model.dart';

class AlarmHistoryWidget extends StatefulWidget {
  const AlarmHistoryWidget({super.key});

  @override
  State<AlarmHistoryWidget> createState() => _AlarmHistoryWidgetState();
}

class _AlarmHistoryWidgetState extends State<AlarmHistoryWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final AlarmController _alarmController = Get.put(AlarmController());
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final RxList<AlarmModel> _alarms = <AlarmModel>[].obs;
  final RxBool _isLoading = true.obs;

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  /// Creates a new active alarm based on settings from a previous alarm
  Future<void> _reuseAlarm(AlarmModel alarm, bool isEnabled) async {
    if (!isEnabled) {
      // Find and delete the active alarm with matching time and settings
      try {
        final activeAlarms = _alarmController.getActiveAlarms();
        final matchingAlarm = activeAlarms.firstWhere(
          (active) => 
              active.time.hour == alarm.time.hour && 
              active.time.minute == alarm.time.minute &&
              active.soundId == alarm.soundId,
          orElse: () => AlarmModel(time: DateTime.now(), id: -1),
        );
        
        if (matchingAlarm.id != null && matchingAlarm.id != -1) {
          await _databaseHelper.deleteAlarm(matchingAlarm.id!);
          await _alarmController.loadAlarms();
          _alarmController.refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
          _showFeedbackMessage('Alarm disabled');
        }
        
        await _loadAlarms();
      } catch (e) {
        debugPrint('Error disabling alarm: $e');
        _showFeedbackMessage('Failed to disable alarm', isError: true);
      }
      return;
    }
    
    try {
      final DateTime now = DateTime.now();
      DateTime newTime;

      final bool isTimePassedForToday = alarm.time.hour < now.hour ||
          (alarm.time.hour == now.hour && alarm.time.minute <= now.minute);

      if (isTimePassedForToday) {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        newTime = DateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          alarm.time.hour,
          alarm.time.minute,
        );
      } else {
        newTime = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.time.hour,
          alarm.time.minute,
        );
      }

      final newAlarm = AlarmModel(
        id: null,
        time: newTime,
        isEnabled: true,
        soundId: alarm.soundId,
        nfcRequired: alarm.nfcRequired,
        daysActive: List<String>.from(alarm.daysActive),
        isForToday: true,
      );

      await _alarmController.createAlarm(newAlarm);
      await Future.delayed(const Duration(milliseconds: 300));

      await _alarmController.loadAlarms();
      _alarmController.refreshTimestamp.value =
          DateTime.now().millisecondsSinceEpoch;
      await _loadAlarms();

      // Get.toNamed(AppConstants.home);
      _showFeedbackMessage('Alarm reused successfully');
    } catch (e) {
      debugPrint('Error reusing alarm: $e');
      _showFeedbackMessage('Failed to reuse alarm: ${e.toString()}',
          isError: true);
    }
  }

  /// Loads all past or inactive alarms from the database
  Future<void> _loadAlarms() async {
    _isLoading.value = true;

    try {
      final allAlarms = await _databaseHelper.getAllAlarms();
      final DateTime now = DateTime.now();

      final historyAlarms = allAlarms.where((alarm) {
        return !alarm.isEnabled ||
            (!alarm.isRepeating && alarm.time.isBefore(now));
      }).toList();

      _alarms.value = historyAlarms;
      _isLoading.value = false;
    } catch (e) {
      debugPrint('Error loading alarms: $e');
      _isLoading.value = false;
      _showFeedbackMessage('Error loading alarms', isError: true);
    }
  }

  /// Permanently removes an alarm from the database
  Future<void> _deleteAlarm(int? id) async {
    if (id == null) return;

    try {
      await _databaseHelper.deleteAlarm(id);
      _showFeedbackMessage('Alarm deleted successfully');
      _loadAlarms();
    } catch (e) {
      debugPrint('Error deleting alarm: $e');
      _showFeedbackMessage('Failed to delete alarm', isError: true);
    }
  }

  /// Displays a time widget with hours, minutes and AM/PM indicator
  Widget _formatTimeWidget(DateTime? time, {double scaleFactor = 1.0}) {
    if (time == null) return const Text('');

    final hour =
    time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';

    final timeFontSize = 35.0 * scaleFactor;
    final periodFontSize = 10.0 * scaleFactor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$hour:$minute',
          style: GoogleFonts.interTight(
            color: Colors.white,
            fontSize: timeFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          period,
          style: GoogleFonts.interTight(
            color: Colors.white,
            fontSize: periodFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Shows a feedback message to the user
  void _showFeedbackMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            backgroundColor: isError ? Colors.red : null,
          ),
        );
      }
    });
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
            'Alarm History',
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
    return Obx(() {
      if (_isLoading.value) {
        return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).primaryColor,
            ));
      }

      if (_alarms.isEmpty) {
        return Center(
          child: Text(
            'No alarm history found',
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
    });
  }

  /// Builds an individual alarm card with time display and action buttons
  Widget _buildAlarmCard(AlarmModel alarm) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth < 320 ? 0.75 :
    screenWidth < 360 ? 0.85 :
    screenWidth < 400 ? 0.95 : 1.0;

    return Material(
      color: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(16 * scaleFactor),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: Theme.of(context).primaryColor,
                    size: 26 * scaleFactor,
                  ),
                  SizedBox(width: 10 * scaleFactor),
                  _formatTimeWidget(alarm.time, scaleFactor: scaleFactor),
                ],
              ),
              _buildActionButtons(alarm, scaleFactor: scaleFactor),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds action buttons (Delete and Toggle)
  Widget _buildActionButtons(AlarmModel alarm, {double scaleFactor = 1.0}) {
    final buttonHeight = 36.0 * scaleFactor;
    final buttonWidth = max(70.0 * scaleFactor, 60.0);
    final fontSize = 14.0 * scaleFactor;
    final horizontalPadding = 8.0 * scaleFactor;

    // Check if the alarm exists in active alarms
    bool isActive = _alarmController.getActiveAlarms().any(
        (activeAlarm) => 
            activeAlarm.time.hour == alarm.time.hour && 
            activeAlarm.time.minute == alarm.time.minute &&
            activeAlarm.soundId == alarm.soundId
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: () => _deleteAlarm(alarm.id),
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
              'Delete',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
        SizedBox(width: 8 * scaleFactor),
        Switch(
          value: isActive,
          onChanged: (value) => _reuseAlarm(alarm, value),
          activeColor: Colors.white,
          activeTrackColor: Theme.of(context).primaryColor,
          inactiveThumbColor: Colors.grey[400],
          inactiveTrackColor: Colors.grey[700],
        ),
      ],
    );
  }
}

/// Extension to add space between widgets in a list
extension WidgetListExtension on List<Widget> {
  List<Widget> divide(Widget divider) {
    if (length <= 1) return this;

    final newList = <Widget>[];
    for (var i = 0; i < length; i++) {
      newList.add(this[i]);
      if (i != length - 1) {
        newList.add(divider);
      }
    }
    return newList;
  }
}


double max(double a, double b) {
  return a > b ? a : b;
}