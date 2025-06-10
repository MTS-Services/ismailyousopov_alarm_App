import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:alarm/alarm.dart';
import '../../../controllers/alarm/alarm_controller.dart';
import '../../../controllers/nfc/nfc_controller.dart';
import '../../../core/services/background_service.dart';
import '../../../core/constants/asset_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class AlarmStopScreen extends StatefulWidget {
  final int alarmId;
  final int soundId;

  const AlarmStopScreen({
    super.key,
    required this.alarmId,
    this.soundId = 1,
  });

  @override
  State<AlarmStopScreen> createState() => _AlarmStopWidgetState();

  static AlarmStopScreen fromArguments(dynamic arguments) {
    // Handle arguments whether they're passed as a map or directly
    if (arguments is Map<String, dynamic>) {
      return AlarmStopScreen(
        alarmId: arguments['alarmId'] ?? 0,
        soundId: arguments['soundId'] ?? 1,
      );
    } else if (arguments is int) {
      return AlarmStopScreen(alarmId: arguments);
    } else {
      // Default fallback
      return const AlarmStopScreen(alarmId: 0);
    }
  }
}

class _AlarmStopWidgetState extends State<AlarmStopScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  final NFCController _nfcController = Get.put(NFCController());
  final AlarmController _alarmController = Get.put(AlarmController());
  final TextEditingController _backupCodeController = TextEditingController();

  final RxBool isVerifying = false.obs;
  final RxBool showErrorMessage = false.obs;
  final RxString errorMessage = ''.obs;
  final RxBool nfcRequired = false.obs;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Get the active alarm ID and sound ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final isOpenedFromNotification =
          prefs.getBool('flutter.direct_to_stop') ?? false;

      // If opened from notification, use the stored active alarm ID and sound ID
      int alarmId = widget.alarmId;
      int soundId = widget.soundId;

      if (isOpenedFromNotification) {
        alarmId = prefs.getInt('flutter.active_alarm_id') ?? alarmId;
        soundId = prefs.getInt('flutter.active_alarm_sound') ?? soundId;

        // Clear the flag since we've handled it
        await prefs.remove('flutter.direct_to_stop');
      }

      // Ensure alarm is active
      await _ensureAlarmIsActive();

      // Get the alarm object to check if NFC is required
      final alarm = _alarmController.getAlarmById(alarmId);
      if (alarm != null) {
        nfcRequired.value = alarm.nfcRequired;
        if (alarm.nfcRequired) {
          // NFC is required - initialize the NFC verification process
          await _startNfcVerification();
        }
        // If NFC is not required, we'll show a simple stop button
      }
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _nfcController.stopNfcScan();
    _backupCodeController.dispose();
    super.dispose();
  }

  Future<void> _ensureAlarmIsActive() async {
    try {
      // Get the active alarm ID and sound ID from SharedPreferences first
      final prefs = await SharedPreferences.getInstance();

      // Set active alarm IDs - prefer stored values for consistency
      final storedAlarmId =
          prefs.getInt('flutter.active_alarm_id') ?? widget.alarmId;
      final storedSoundId =
          prefs.getInt('flutter.active_alarm_sound') ?? widget.soundId;

      // Always update with the most current values
      await prefs.setInt('flutter.active_alarm_id', storedAlarmId);
      await prefs.setInt('flutter.active_alarm_sound', storedSoundId);

      // Update the controller
      _alarmController.activeAlarmId.value = storedAlarmId;

      final isActive = await AlarmBackgroundService.isAlarmActive();
      if (!isActive) {
        // If alarm isn't active, start it
        await AlarmBackgroundService.forceStartAlarmIfNeeded(
            storedAlarmId, storedSoundId);
      }
    } catch (e) {
      debugPrint('Error ensuring alarm is active: $e');
    }
  }

  /// Direct method to stop the alarm without NFC verification
  Future<void> _stopAlarm() async {
    try {
      // Use the enhanced background service stop method which properly coordinates all stop operations
      await AlarmBackgroundService.stopAlarm();

      // Stop the alarm sound in Flutter as well
      _alarmController.stopAlarmSound();

      // Update the database state
      await _alarmController.stopAlarm(widget.alarmId, soundId: widget.soundId);

      // Navigate back to home
      Get.offNamed(AppConstants.home);
    } catch (e) {
      debugPrint('Error stopping alarm: $e');
      // Try emergency stop as a fallback
      await AlarmBackgroundService.emergencyStopAllAlarms();
      Get.offNamed(AppConstants.home);
    }
  }

  /// start nfc verification
  Future<void> _startNfcVerification() async {
    isVerifying.value = true;
    showErrorMessage.value = false;

    if (!_nfcController.isNfcAvailable.value) {
      isVerifying.value = false;
      showErrorMessage.value = true;
      errorMessage.value =
          'NFC is not available on this device. Please use backup code.';
      return;
    }

    final success = await _nfcController.startAlarmVerification(widget.alarmId);

    if (success) {
      try {
        // Use the enhanced background service stop method which properly coordinates all stop operations
        await AlarmBackgroundService.stopAlarm();

        // Stop the alarm sound in Flutter as well
        _alarmController.stopAlarmSound();

        // Update the database state
        await _alarmController.stopAlarm(widget.alarmId,
            soundId: widget.soundId);

        // Navigate back to home
        Get.offNamed(AppConstants.home);
      } catch (e) {
        debugPrint('Error stopping alarm: $e');
        // Try emergency stop as a fallback
        await AlarmBackgroundService.emergencyStopAllAlarms();
        Get.offNamed(AppConstants.home);
      }
    } else {
      isVerifying.value = false;
      showErrorMessage.value = true;
      errorMessage.value =
          'NFC verification failed. Please try again or use backup code.';
    }
  }

  /// verify backup code
  void _verifyBackupCode() async {
    final code = _backupCodeController.text.trim();

    if (_nfcController.verifyBackupCode(code)) {
      try {
        // Use the enhanced background service stop method which properly coordinates all stop operations
        await AlarmBackgroundService.stopAlarm();

        // Stop the alarm sound in Flutter as well
        _alarmController.stopAlarmSound();

        // Update the database state
        await _alarmController.stopAlarm(widget.alarmId,
            soundId: widget.soundId);

        // Navigate back to home
        Get.offNamed(AppConstants.home);
      } catch (e) {
        debugPrint('Error stopping alarm: $e');
        // Try emergency stop as a fallback
        await AlarmBackgroundService.emergencyStopAllAlarms();
        Get.offNamed(AppConstants.home);
      }
    } else {
      showErrorMessage.value = true;
      errorMessage.value = 'Invalid backup code. Please try again.';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid backup code. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// backup code info
  void _showBackupCodeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.85;

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Can't turn off the alarm with the NFC tag? Enter your Turn Off KEY to disable the alarm.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You can also find this key on our website\nEARLYUPTAG.COM',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _backupCodeController,
                  decoration: InputDecoration(
                    hintText: 'Enter Turn Off Key',
                    hintStyle: GoogleFonts.inter(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _verifyBackupCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B1F41),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: Text(
                      'Turn Off Alarm',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;

    return WillPopScope(
      onWillPop: () async {
        // Check if alarm is still active
        final isActive = await AlarmBackgroundService.isAlarmActive();
        if (isActive) {
          // Show a message to the user
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please stop the alarm before navigating back'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        return true;
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                // Do nothing - prevent navigation away from stop alarm screen
              },
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nfcRequired.value
                      ? Padding(
                          padding: EdgeInsets.only(
                            left: constraints.maxWidth * 0.06,
                            top: constraints.maxHeight * 0.02,
                          ),
                          child: GestureDetector(
                            onTap: _showBackupCodeDialog,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 36,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Help!',
                                  style: GoogleFonts.inter(
                                    color: Colors.black,
                                    fontSize: isSmallScreen ? 20 : 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox(),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Obx(() {
                              // Show different UI based on whether NFC is required
                              if (nfcRequired.value) {
                                // NFC required UI - show NFC scanning interface
                                return Stack(
                                  children: [
                                    Container(
                                      width: constraints.maxWidth * 0.6,
                                      height: constraints.maxHeight * 0.4,
                                      constraints: const BoxConstraints(
                                        maxWidth: 250,
                                        maxHeight: 320,
                                        minWidth: 180,
                                        minHeight: 240,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        boxShadow: const [
                                          BoxShadow(
                                            blurRadius: 4,
                                            color: Color(0xFF040000),
                                            offset: Offset(0, 2),
                                          )
                                        ],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Stack(
                                        children: [
                                          Align(
                                            alignment: Alignment.center,
                                            child: Obx(() => Icon(
                                                  _nfcController
                                                          .verificationSuccess
                                                          .value
                                                      ? Icons
                                                          .check_circle_outline
                                                      : Icons.nfc_rounded,
                                                  color: Colors.white,
                                                  size:
                                                      isSmallScreen ? 160 : 220,
                                                )),
                                          ),
                                          Positioned(
                                            top: isSmallScreen ? 12 : 16,
                                            left: 0,
                                            right: 0,
                                            child: Obx(() => Text(
                                                  _nfcController
                                                          .verificationSuccess
                                                          .value
                                                      ? 'Success!'
                                                      : 'Scan to stop',
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white,
                                                    fontSize:
                                                        isSmallScreen ? 12 : 16,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                )),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Reactive shimmer effect
                                    Obx(
                                      () => _nfcController
                                              .verificationSuccess.value
                                          ? const SizedBox()
                                          : Positioned.fill(
                                              child: AnimatedBuilder(
                                                animation: _shimmerController,
                                                builder: (context, child) {
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                      gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                        colors: const [
                                                          Colors.transparent,
                                                          Colors.white10,
                                                          Colors.white24,
                                                          Colors.white10,
                                                          Colors.transparent,
                                                        ],
                                                        stops: [
                                                          0.0,
                                                          _shimmerController
                                                                  .value -
                                                              0.2,
                                                          _shimmerController
                                                              .value,
                                                          _shimmerController
                                                                  .value +
                                                              0.2,
                                                          1.0,
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                    ),
                                  ],
                                );
                              } else {
                                // Regular alarm stop UI with simple stop button
                                return Container(
                                  width: constraints.maxWidth * 0.6,
                                  height: constraints.maxWidth * 0.6,
                                  constraints: const BoxConstraints(
                                    maxWidth: 250,
                                    maxHeight: 250,
                                    minWidth: 200,
                                    minHeight: 200,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(32),
                                          onTap: _stopAlarm,
                                          child: Container(
                                            width: constraints.maxWidth * 0.4,
                                            height: constraints.maxWidth * 0.4,
                                            constraints: const BoxConstraints(
                                              maxWidth: 220,
                                              maxHeight: 220,
                                              minWidth: 180,
                                              minHeight: 180,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(12),
                                                topRight: Radius.circular(52),
                                                bottomLeft: Radius.circular(52),
                                                bottomRight:
                                                    Radius.circular(52),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  blurRadius: 8,
                                                  color: Colors.black
                                                      .withOpacity(0.2),
                                                  offset: const Offset(0, 4),
                                                )
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.power_settings_new,
                                              color: Colors.white,
                                              size: isSmallScreen ? 60 : 80,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // const SizedBox(height: 16),
                                      // Container(
                                      //   padding: const EdgeInsets.symmetric(
                                      //     horizontal: 20,
                                      //     vertical: 8,
                                      //   ),
                                      //   decoration: BoxDecoration(
                                      //     color: Colors.black,
                                      //     borderRadius: BorderRadius.circular(30),
                                      //   ),
                                      //   child: Text(
                                      //     'Tab the button to stop the alarm',
                                      //     style: GoogleFonts.inter(
                                      //       color: Colors.white,
                                      //       fontSize: isSmallScreen ? 12 : 14,
                                      //       fontWeight: FontWeight.w500,
                                      //     ),
                                      //   ),
                                      // ),
                                    ],
                                  ),
                                );
                              }
                            }),
                            Padding(
                              padding: EdgeInsets.only(
                                top: constraints.maxHeight * 0.03,
                                left: constraints.maxWidth * 0.05,
                                right: constraints.maxWidth * 0.05,
                              ),
                              child: Obx(() {
                                if (nfcRequired.value) {
                                  // Show message for NFC scan
                                  return Container(
                                    width: constraints.maxWidth * 0.9,
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Center(
                                      child: Obx(() {
                                        return Text(
                                          showErrorMessage.value
                                              ? errorMessage.value
                                              : _nfcController
                                                      .isVerifyingAlarm.value
                                                  ? 'Hold your device near the NFC tag'
                                                  : 'Press retry to scan again or use backup code',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: isSmallScreen ? 12 : 14,
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                } else {
                                  // Show instruction for regular stop
                                  return Container(
                                    width: constraints.maxWidth * 0.9,
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Tap the button to stop the alarm',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: isSmallScreen ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }),
                            ),
                            Obx(() {
                              if (nfcRequired.value &&
                                  !_nfcController.isVerifyingAlarm.value &&
                                  !_nfcController.verificationSuccess.value) {
                                return Padding(
                                  padding: EdgeInsets.only(
                                    top: constraints.maxHeight * 0.03,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _startNfcVerification,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isSmallScreen ? 20 : 30,
                                        vertical: isSmallScreen ? 12 : 15,
                                      ),
                                    ),
                                    child: Text(
                                      'Retry Scan',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: isSmallScreen ? 14 : 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              } else {
                                return const SizedBox();
                              }
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
