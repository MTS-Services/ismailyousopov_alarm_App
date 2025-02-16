import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 305,
      child: Drawer(
        backgroundColor: Colors.white,
        elevation: 14,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(0, 59, 0, 0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(22, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.pushNamed(context, 'NFC-SETTINGS');
                        },
                        child: const Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Icon(
                                  Icons.nfc_rounded,
                                  color: Color(0xFF811F3E),
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Text(
                                  'NFC',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(6, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.pushNamed(context, 'Alaram-Sounds');
                        },
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: FaIcon(
                                  FontAwesomeIcons.music,
                                  color: Color(0xFF811F3E),
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Text(
                                  'Alarm',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(0, 6, 0, 0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(22, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          // Language setting functionality
                        },
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Icon(
                                  Icons.public,
                                  color: Color(0xFF811F3E),
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Text(
                                  'Language',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(6, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.pushNamed(context, 'Statistics');
                        },
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Icon(
                                  Icons.query_stats_rounded,
                                  color: Color(0xFF811F3E),
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, 15),
                                child: Text(
                                  'Statistics',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              thickness: 2,
              color: Color(0xFFCBCED6),
            ),
            ListTile(
              leading: Icon(Icons.info_outlined),
              title: Text(
                'About the app',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                ),
              ),
              onTap: () => Navigator.pushNamed(context, 'ABOUTAPP'),
            ),
            ListTile(
              leading: Icon(Icons.update),
              title: Text(
                'App version',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                ),
              ),
              onTap: () => Navigator.pushNamed(context, 'Uppdate-Info'),
            ),
            ListTile(
              leading: Icon(Icons.polyline_sharp),
              title: Text(
                'Terms and Conditions',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                ),
              ),
              onTap: () {},
            ),
            ListTile(
              leading: FaIcon(FontAwesomeIcons.handsHelping),
              title: Text(
                'Help',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                ),
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}