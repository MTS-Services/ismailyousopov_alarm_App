import 'package:alarm/views/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AlarmHistoryWidget extends StatefulWidget {
  const AlarmHistoryWidget({super.key});

  @override
  State<AlarmHistoryWidget> createState() => _AlarmHistoryWidgetState();
}

class _AlarmHistoryWidgetState extends State<AlarmHistoryWidget> {
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
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: Theme.of(context).textTheme.bodyLarge?.color,
              size: 35,
            ),
            onPressed: () {
              Get.to(HomeScreen());
            },
          ),
          title: Text(
            'Alarm History',
            style: TextStyle(
              fontFamily: 'Inter Tight',
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var time in ['06:34', '12:32', '08:00', '09:29', '05:00', '16:00', '19:32'])
                    Material(
                      color: Colors.transparent,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        decoration: BoxDecoration(
                          color: const Color(0xFF811F3E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 22),
                                child: Text(
                                  time,
                                  style: const TextStyle(
                                    fontFamily: 'Inter Tight',
                                    color: Colors.white,
                                    fontSize: 35,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () {
                                      print('Delete button pressed...');
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      padding: const EdgeInsets.all(8),
                                      minimumSize: const Size(80, 36),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Color(0xFFF9F8F8),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () {
                                      print('Use button pressed...');
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      padding: const EdgeInsets.all(8),
                                      minimumSize: const Size(80, 36),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      'Use',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Theme.of(context).textTheme.bodyMedium?.color,
                                        fontWeight: FontWeight.w800,
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
                ].divide(const SizedBox(height: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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