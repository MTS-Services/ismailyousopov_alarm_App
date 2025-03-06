import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../controllers/alarm/alarm_controller.dart';
import '../../../models/alarm/alarm_model.dart';
import '../../../core/constants/asset_constants.dart';
import 'sound_manager.dart';

class AlarmSetScreen extends StatefulWidget {
  const AlarmSetScreen({super.key});

  @override
  State<AlarmSetScreen> createState() => _AlarmSetScreenState();
}

class _AlarmSetScreenState extends State<AlarmSetScreen> {
  final AlarmController _alarmController = Get.put(AlarmController());
  bool _nfcEnabled = false;
  int _selectedSoundId = 1;
  TimeOfDay _selectedTime = TimeOfDay.now();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedSoundName = SoundManager.getSoundName(1);

  @override
  void dispose() {
    // Stop any playing sound when leaving the screen
    _alarmController.stopAlarmSound();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              hourMinuteTextColor: Colors.white,
              dialHandColor: Theme.of(context).primaryColor,
              dialBackgroundColor: Colors.grey[800],
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _saveAlarm() async {
    // Stop any playing preview sound
    _alarmController.stopAlarmSound();

    final now = DateTime.now();
    DateTime selectedDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    print('Current Time: $now');
    print('Selected Time: $selectedDateTime');
    print(_selectedSoundId);

    // If the selected time is in the past, schedule for the next day
    if (selectedDateTime.isBefore(now)) {
      selectedDateTime = selectedDateTime.add(const Duration(days: 1));
      print('Adjusted Selected Time (next day): $selectedDateTime');
    }

    final newAlarm = AlarmModel(
      time: selectedDateTime,
      isEnabled: true,
      soundId: _selectedSoundId,
      nfcRequired: _nfcEnabled,
      daysActive: [],
    );

    await _alarmController.createAlarm(newAlarm);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 30),
            onPressed: () {
              _alarmController.stopAlarmSound();
              Get.back();
            },
          ),
          title: Text(
            'Set Alarm',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Time Selection Circle
                  GestureDetector(
                    onTap: () => _selectTime(context),
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _selectedTime.format(context),
                          style: const TextStyle(
                            fontFamily: 'Inter Tight',
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Settings Container
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // NFC Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.nfc,
                                  color: Theme.of(context).primaryColor,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'NFC to Stop',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: _nfcEnabled,
                              onChanged: (value) => setState(() => _nfcEnabled = value),
                              activeColor: Colors.white,
                              activeTrackColor: Colors.black,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Sound Selection
                        InkWell(
                          onTap: () async {
                            // Stop current playing sound before going to sound selection
                            _alarmController.stopAlarmSound();
                            final result = await Get.toNamed(AppConstants.alarmSounds);
                            if (result != null) {
                              setState(() {
                                _selectedSoundId = result;
                                _selectedSoundName = SoundManager.getSoundName(_selectedSoundId);
                              });
                              _alarmController.playAlarmSound(_selectedSoundId);
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    color: Theme.of(context).primaryColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Alarm Sound',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Text(
                                        _selectedSoundName,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          _alarmController.stopAlarmSound();
                          Get.back();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          fixedSize: const Size(150, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _saveAlarm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          fixedSize: const Size(150, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                            side: const BorderSide(color: Colors.black),
                          ),
                        ),
                        child: Text(
                          'Save',
                          style: GoogleFonts.inter(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}