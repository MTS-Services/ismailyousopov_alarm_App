import 'package:alarm/views/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AlarmSetScreen extends StatefulWidget {
  const AlarmSetScreen({Key? key}) : super(key: key);

  @override
  State<AlarmSetScreen> createState() => _AlarmSetScreenState();
}

class _AlarmSetScreenState extends State<AlarmSetScreen> {
  bool _nfcEnabled = false;
  final scaffoldKey = GlobalKey<ScaffoldState>();

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
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Material(
                    elevation: 4,
                    shape: CircleBorder(),
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: const BoxDecoration(
                        color: Colors.white, // warning color
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '10:30',
                          style: TextStyle(
                            fontFamily: 'Inter Tight',
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Settings Container
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Material(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          // NFC Switch Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.nfc,
                                    color: Color(0xFF811F3E),
                                    size: 24,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Enable NFC',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _nfcEnabled,
                                onChanged: (newValue) {
                                  setState(() => _nfcEnabled = newValue);
                                },
                                activeColor: Colors.white,
                                activeTrackColor: Colors.black,
                              ),
                            ],
                          ),
                          SizedBox(height: 24),

                          // Sound Selection Row
                          InkWell(
                            onTap: () {
                              Get.toNamed('/alarm-sound');
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.music_note,
                                      color: Color(0xFF811F3E),
                                      size: 24,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Choose Sound',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
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
                  ),
                ),
                const SizedBox(height: 32),

                // Button Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Cancel Button
                      ElevatedButton(
                        onPressed: () {
                          Get.to(const HomeScreen());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF811F3E),
                          fixedSize: Size(125, 50),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: 'Inter Tight',
                            color: Colors.white,
                          ),
                        ),
                      ),

                      // Save Button
                      ElevatedButton(
                        onPressed: () {
                          Get.to(const HomeScreen());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          fixedSize: Size(125, 50),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                            side: const BorderSide(
                              color: Colors.black,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontFamily: 'Inter Tight',
                            color: Colors.black,
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
      ),
    );
  }
}