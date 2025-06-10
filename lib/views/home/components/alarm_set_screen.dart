import 'package:alarmapp/views/home/components/scan_nfc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../controllers/alarm/alarm_controller.dart';
import '../../../controllers/nfc/nfc_controller.dart';
import '../../../models/alarm/alarm_model.dart';
import '../../../core/constants/asset_constants.dart';
import '../../../core/services/sound_manager.dart';

class AlarmSetScreen extends StatefulWidget {
  const AlarmSetScreen({super.key});

  @override
  State<AlarmSetScreen> createState() => _AlarmSetScreenState();
}

class _AlarmSetScreenState extends State<AlarmSetScreen> {
  final AlarmController _alarmController = Get.find<AlarmController>();
  bool _nfcEnabled = false;
  DateTime _selectedDateTime = DateTime.now();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  AlarmModel? _editingAlarm;
  bool _isEditing = false;
  final NFCController nfcController = Get.put(NFCController());

  @override
  void initState() {
    super.initState();
    if (Get.arguments != null && Get.arguments is AlarmModel) {
      _editingAlarm = Get.arguments as AlarmModel;
      _isEditing = true;
      _selectedDateTime = _editingAlarm!.time;
      _alarmController.updateSelectedSound(_editingAlarm!.soundId);
      _nfcEnabled = _editingAlarm!.nfcRequired;
    }
  }

  @override
  void dispose() {
    _alarmController.stopAlarmSound();
    super.dispose();
  }

  /// save alarm
  Future<void> _saveAlarm() async {
    _alarmController.stopAlarmSound();
    final now = DateTime.now();
    DateTime selectedDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedDateTime.hour,
      _selectedDateTime.minute,
    );

    if (selectedDateTime.isBefore(now) &&
        (_editingAlarm == null || _editingAlarm!.daysActive.isEmpty)) {
      selectedDateTime = selectedDateTime.add(const Duration(days: 1));
    }

    if (_isEditing) {
      final updatedAlarm = AlarmModel(
        id: _editingAlarm!.id,
        time: selectedDateTime,
        isEnabled: true,
        soundId: _alarmController.selectedSoundForNewAlarm.value,
        nfcRequired: _nfcEnabled,
        daysActive: _editingAlarm!.daysActive,
      );

      await _alarmController.updateAlarm(updatedAlarm);
    } else {
      final newAlarm = AlarmModel(
        time: selectedDateTime,
        isEnabled: true,
        soundId: _alarmController.selectedSoundForNewAlarm.value,
        nfcRequired: _nfcEnabled,
        daysActive: [],
      );

      await _alarmController.createAlarm(newAlarm);
    }

    Get.back();
  }

  void _handleNfcSwitch(bool value) async {
    if (value) {
      if (!nfcController.isNfcAvailable.value) {
        Get.snackbar(
          'NFC Not Available',
          'Your device does not support NFC or NFC is disabled.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // Check if any tag is already registered system-wide
      await nfcController.checkIfNfcRegistered();
      if (nfcController.hasRegisteredNfcTag.value) {
        // If a tag is already registered, simply enable NFC for this alarm
        setState(() {
          _nfcEnabled = true;
        });
        Get.snackbar(
          'NFC Enabled',
          'This alarm will now require NFC to stop',
          backgroundColor: Colors.green[100],
          colorText: Colors.black,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // Ask user if they want to register an NFC tag
      final shouldRegister = await _showRegisterNfcDialog();
      if (shouldRegister != true) {
        // User declined to register tag, so don't enable NFC
        return;
      } else if (shouldRegister == true) {
        int tempAlarmId = DateTime.now().millisecondsSinceEpoch;
        Get.to(() => AddNFCWidget(alarmId: tempAlarmId));
      }

      // If the result is true, a tag was registered successfully
      // if (result == true) {
      //   setState(() {
      //     _nfcEnabled = true;
      //   });
      // } else {
      //   // If registration was canceled or unsuccessful, check if any w is registered
      //   await nfcController.checkIfNfcRegistered();
      //   setState(() {
      //     _nfcEnabled = nfcController.hasRegisteredNfcTag.value;
      //   });
      // }
    } else {
      // Turn off NFC requirement
      setState(() {
        _nfcEnabled = false;
      });
    }
  }

  /// Show dialog asking user if they want to register an NFC tag
  Future<bool?> _showRegisterNfcDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Register NFC Tag',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'To use NFC to stop the alarm, you need to register an NFC tag first. Would you like to register a tag now?',
            style: GoogleFonts.inter(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'No',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Yes, Register',
                style: GoogleFonts.inter(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
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
            _isEditing ? 'Edit Alarm' : 'Set Alarm',
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
                  Container(
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 200,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Hour Picker
                              SizedBox(
                                width: 70,
                                child: CupertinoPicker(
                                  magnification: 1.2,
                                  squeeze: 1.2,
                                  useMagnifier: true,
                                  itemExtent: 40,
                                  looping: false,
                                  onSelectedItemChanged: (int index) {
                                    setState(() {
                                      _selectedDateTime = DateTime(
                                        _selectedDateTime.year,
                                        _selectedDateTime.month,
                                        _selectedDateTime.day,
                                        index,
                                        _selectedDateTime.minute,
                                      );
                                    });
                                  },
                                  scrollController: FixedExtentScrollController(
                                    initialItem: _selectedDateTime.hour,
                                  ),
                                  children: List<Widget>.generate(
                                    24,
                                    (int index) {
                                      return Center(
                                        child: Text(
                                          index.toString().padLeft(2, '0'),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              const Text(
                                ":",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),

                              // Minute Picker
                              SizedBox(
                                width: 70,
                                child: CupertinoPicker(
                                  magnification: 1.2,
                                  squeeze: 1.2,
                                  useMagnifier: true,
                                  itemExtent: 40,
                                  looping: true,
                                  onSelectedItemChanged: (int index) {
                                    setState(() {
                                      _selectedDateTime = DateTime(
                                        _selectedDateTime.year,
                                        _selectedDateTime.month,
                                        _selectedDateTime.day,
                                        _selectedDateTime.hour,
                                        index,
                                      );
                                    });
                                  },
                                  scrollController: FixedExtentScrollController(
                                    initialItem: _selectedDateTime.minute,
                                  ),
                                  children: List<Widget>.generate(
                                    60,
                                    (int index) {
                                      return Center(
                                        child: Text(
                                          index.toString().padLeft(2, '0'),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
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
                              onChanged: _handleNfcSwitch,
                              activeColor: Colors.white,
                              activeTrackColor: Colors.black,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Sound Selection
                        InkWell(
                          onTap: () async {
                            _alarmController.stopAlarmSound();
                            final result = await Get.toNamed(
                              AppConstants.alarmSounds,
                              arguments: _alarmController
                                  .selectedSoundForNewAlarm.value,
                            );
                            if (result != null) {
                              _alarmController.updateSelectedSound(result);
                              _alarmController.playAlarmSound(result);
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Alarm Sound',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Obx(() => Text(
                                            _alarmController
                                                .selectedSoundName.value,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          )),
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

                        // Volume Control
                        const SizedBox(height: 20),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Volume',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Colors.black,
                                  ),
                                ),
                                Obx(() => Text(
                                      '${_alarmController.currentAlarmVolume.value}%',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    )),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.volume_mute,
                                    color: Colors.black,
                                  ),
                                  onPressed: () {
                                    _alarmController.updateAlarmVolume(0);
                                  },
                                ),
                                Expanded(
                                  child: Obx(() => SliderTheme(
                                        data: SliderThemeData(
                                          thumbColor: Colors.black,
                                          activeTrackColor: Colors.black,
                                          inactiveTrackColor: Colors.grey[300],
                                          trackHeight: 4.0,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                            enabledThumbRadius: 8.0,
                                          ),
                                        ),
                                        child: Slider(
                                          value: _alarmController
                                              .currentAlarmVolume.value
                                              .toDouble(),
                                          min: 0,
                                          max: 100,
                                          onChanged: (value) {
                                            _alarmController.updateAlarmVolume(
                                                value.round());
                                          },
                                        ),
                                      )),
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.volume_up,
                                    color: Colors.black,
                                  ),
                                  onPressed: () {
                                    _alarmController.updateAlarmVolume(100);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _saveAlarm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          fixedSize: const Size(150, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                            side: const BorderSide(color: Colors.black),
                          ),
                        ),
                        child: Text(
                          _isEditing ? 'Update' : 'Save',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
