import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../controllers/alarm/alarm_controller.dart';

class AlarmSoundsWidget extends StatefulWidget {
  const AlarmSoundsWidget({super.key});

  @override
  State<AlarmSoundsWidget> createState() => _AlarmSoundsWidgetState();
}

class _AlarmSoundsWidgetState extends State<AlarmSoundsWidget> {
  final AlarmController _alarmController = Get.find<AlarmController>();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int? selectedBubbleIndex;

  final List<Map<String, dynamic>> bubbleConfigs = [
    {
      'alignment': const Alignment(-0.52, -0.64),
      'size': 83.0,
      'colors': [const Color(0xFFEE20D0), null],
      'soundId': 1,
      'soundPath': 'alarm_sounds/sound_1.wav',
    },
    {
      'alignment': const Alignment(0.66, -0.57),
      'size': 120.0,
      'colors': [const Color(0xFF4b39ef), null],
      'soundId': 2,
      'soundPath': 'alarm_sounds/sound_2.wav',
    },
    {
      'alignment': const Alignment(0.98, -0.19),
      'size': 109.0,
      'colors': [null, Colors.black],
      'soundId': 3,
      'soundPath': 'alarm_sounds/sound_3.wav',
    },
    {
      'alignment': const Alignment(-0.96, -0.25),
      'size': 100.0,
      'colors': [Colors.green, null],
      'soundId': 4,
      'soundPath': 'alarm_sounds/sound_4.wav',
    },
    {
      'alignment': const Alignment(0.11, -0.01),
      'size': 78.0,
      'colors': [Colors.red, null],
      'soundId': 5,
      'soundPath': 'alarm_sounds/sound_5.wav',
    },
    {
      'alignment': const Alignment(0, -0.27),
      'size': 92.0,
      'colors': [const Color(0xFF620A0B), const Color(0xFF40404D)],
      'soundId': 6,
      'soundPath': 'alarm_sounds/sound_6.wav',
    },
    {
      'alignment': const Alignment(-0.92, 0.14),
      'size': 121.0,
      'colors': [const Color(0xFF006039), Colors.amber],
      'soundId': 7,
      'soundPath': 'alarm_sounds/sound_7.wav',
    },
    {
      'alignment': const Alignment(0.61, 0.23),
      'size': 83.0,
      'colors': [null, Colors.green],
      'soundId': 8,
      'soundPath': 'alarm_sounds/sound_8.wav',
    },
  ];

  @override
  void initState() {
    super.initState();

    // Set the selected bubble based on current sound (from arguments or controller)
    int currentSoundId;
    if (Get.arguments != null && Get.arguments is int) {
      currentSoundId = Get.arguments as int;
    } else {
      currentSoundId = _alarmController.selectedSoundForNewAlarm.value;
    }

    // Find the index of the current sound in bubbleConfigs
    selectedBubbleIndex = bubbleConfigs
        .indexWhere((config) => config['soundId'] == currentSoundId);
    if (selectedBubbleIndex == -1)
      selectedBubbleIndex = 0; // Default to first if not found
  }

  @override
  void dispose() {
    _alarmController.stopAlarmSound();
    super.dispose();
  }

  /// preview sound
  Future<void> _playSoundPreview(int soundId) async {
    try {
      await _alarmController.playAlarmSound(soundId, isPreview: true);
    } catch (e) {
      if (kDebugMode) {
        print('Error playing sound preview: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          top: true,
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      margin: const EdgeInsets.all(16),
                      child: Stack(
                        children: [
                          ...List.generate(
                            bubbleConfigs.length,
                            (index) => _buildGradientBubble(
                              context: context,
                              index: index,
                              alignment: bubbleConfigs[index]['alignment'],
                              size: bubbleConfigs[index]['size'],
                              colors: [
                                bubbleConfigs[index]['colors'][0] ??
                                    Theme.of(context).primaryColor,
                                bubbleConfigs[index]['colors'][1] ??
                                    Theme.of(context).cardColor,
                              ],
                            ),
                          ),
                          Align(
                            alignment: const Alignment(-0.01, -0.95),
                            child: Material(
                              color: Colors.transparent,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21),
                              ),
                              child: Container(
                                width: 205,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF020202),
                                  borderRadius: BorderRadius.circular(21),
                                  border: Border.all(
                                    color: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.color ??
                                        Colors.white,
                                  ),
                                ),
                                child: const Center(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        left: 0, right: 0, top: 0, bottom: 0),
                                    child: Text(
                                      'Press any bubble',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: const Alignment(0, 1),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(48, 0, 48, 150),
                              child: ElevatedButton(
                                onPressed: selectedBubbleIndex != null
                                    ? () {
                                        final selectedSoundId =
                                            bubbleConfigs[selectedBubbleIndex!]
                                                ['soundId'];
                                        if (kDebugMode) {
                                          print(
                                              'Selected sound ID: $selectedSoundId');
                                        }

                                        _alarmController.stopAlarmSound();

                                        // Update the controller's persistent sound selection
                                        _alarmController.updateSelectedSound(
                                            selectedSoundId);

                                        Navigator.of(context)
                                            .pop(selectedSoundId);
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(200, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                    side: BorderSide(
                                      color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color ??
                                          Colors.white,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'Select',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 35),
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    size: 35,
                  ),
                  onPressed: () {
                    _alarmController.stopAlarmSound();
                    Get.back();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientBubble({
    required BuildContext context,
    required int index,
    required Alignment alignment,
    required double size,
    required List<Color> colors,
  }) {
    final isSelected = selectedBubbleIndex == index;

    return Align(
      alignment: alignment,
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedBubbleIndex = index;
          });

          // Play sound preview when bubble is tapped
          _playSoundPreview(bubbleConfigs[index]['soundId']);
        },
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          shape: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                stops: const [0, 1],
                begin: const Alignment(0, -1),
                end: const Alignment(0, 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? Colors.red.withValues(alpha: 0.7)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 4,
                  offset: const Offset(0, 3),
                ),
              ],
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color:
                          Theme.of(context).primaryColor.withValues(alpha: 0.5),
                      width: 2,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
