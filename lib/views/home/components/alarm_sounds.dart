import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AlarmSoundsWidget extends StatefulWidget {
  const AlarmSoundsWidget({super.key});

  @override
  State<AlarmSoundsWidget> createState() => _AlarmSoundsWidgetState();
}

class _AlarmSoundsWidgetState extends State<AlarmSoundsWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int? selectedBubbleIndex;

  final List<Map<String, dynamic>> bubbleConfigs = [
    {
      'alignment': const Alignment(-0.52, -0.64),
      'size': 83.0,
      'colors': [const Color(0xFFEE20D0), null],
      'soundId': 1,
    },
    {
      'alignment': const Alignment(0.66, -0.57),
      'size': 120.0,
      'colors': [const Color(0xFF4b39ef), null],
      'soundId': 2,
    },
    {
      'alignment': const Alignment(0.98, -0.19),
      'size': 109.0,
      'colors': [null, Colors.black],
      'soundId': 3,
    },
    {
      'alignment': const Alignment(-0.96, -0.25),
      'size': 100.0,
      'colors': [Colors.green, null],
      'soundId': 4,
    },
    {
      'alignment': const Alignment(0.11, -0.01),
      'size': 78.0,
      'colors': [Colors.red, null],
      'soundId': 5,
    },
    {
      'alignment': const Alignment(0, -0.27),
      'size': 92.0,
      'colors': [const Color(0xFF620A0B), const Color(0xFF40404D)],
      'soundId': 6,
    },
    {
      'alignment': const Alignment(-0.92, 0.14),
      'size': 121.0,
      'colors': [const Color(0xFF006039), Colors.amber],
      'soundId': 7,
    },
    {
      'alignment': const Alignment(0.61, 0.23),
      'size': 83.0,
      'colors': [null, Colors.green],
      'soundId': 8,
    },
  ];

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
              Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
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
                                  bubbleConfigs[index]['colors'][0] ?? Theme.of(context).primaryColor,
                                  bubbleConfigs[index]['colors'][1] ?? Theme.of(context).cardColor,
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
                                  width: 192,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF020202),
                                    borderRadius: BorderRadius.circular(21),
                                    border: Border.all(
                                      color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 9),
                                      child: Text(
                                        'Press any bubble',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
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
                                padding: const EdgeInsets.fromLTRB(48, 0, 48, 150),
                                child: ElevatedButton(
                                  onPressed: selectedBubbleIndex != null
                                      ? () {
                                    final selectedSoundId = bubbleConfigs[selectedBubbleIndex!]['soundId'];
                                    if (kDebugMode) {
                                      print('Selected sound ID: $selectedSoundId');
                                    }
                                    Navigator.of(context).pop(selectedSoundId);
                                  }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(200, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                      side: BorderSide(
                                        color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Select',style: TextStyle(
                                    color: Colors.white
                                  ),),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                  onPressed: () => Get.back(),
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
        },
        child: Material(
          color: Colors.transparent,
          elevation: 2,
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
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                color: Theme.of(context).primaryColor,
                width: 3,
              )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}