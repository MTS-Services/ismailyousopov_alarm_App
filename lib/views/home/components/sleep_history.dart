import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';

class SleepHistoryWidget extends StatefulWidget {
  const SleepHistoryWidget({super.key});

  @override
  SleepHistoryWidgetState createState() => SleepHistoryWidgetState();
}

class SleepHistoryWidgetState extends State<SleepHistoryWidget> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animationController;
  final List<GlobalKey<AnimatedListState>> _listKeys = [
    GlobalKey<AnimatedListState>(),
    GlobalKey<AnimatedListState>(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _animationController.reset();
        _animationController.forward();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedContainer({
    required Widget child,
    required int index,
    required bool show,
  }) {

    final delay = (index * 0.1).clamp(0.0, 1.0);
    final slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Interval(
        delay,
        (delay + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );

    return AnimatedBuilder(
      animation: slideAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - slideAnimation.value)),
          child: Opacity(
            opacity: slideAnimation.value,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildDayContainer({
    required String day,
    required String timeRange,
    Color backgroundColor = Colors.white,
    Color textColor = const Color(0xFF606A85),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: backgroundColor,
          boxShadow: const [
            BoxShadow(
              blurRadius: 3,
              color: Color(0x33000000),
              offset: Offset(0, 1),
            )
          ],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  day,
                  style: GoogleFonts.inter(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Text(
                  timeRange,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.interTight(
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.bottomRight,
                child: FaIcon(
                  FontAwesomeIcons.bed,
                  color: Colors.black,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalHoursCard(String hours) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        width: 100,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [
            BoxShadow(
              blurRadius: 3,
              color: Color(0x33000000),
              offset: Offset(0, 1),
            )
          ],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).textTheme.bodyLarge!.color!,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  'Total hours slept',
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 13,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: RichText(
                  textScaleFactor: MediaQuery.of(context).textScaleFactor,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: hours,
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF15161E),
                          fontSize: 44,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      TextSpan(
                        text: ' Hours/Min',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF606A85),
                          fontSize: 14,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildWeekItems(String hours, List<Map<String, dynamic>> dayData) {
    return [
      _buildAnimatedContainer(
        index: 0,
        show: true,
        child: _buildTotalHoursCard(hours),
      ),
      ...dayData.asMap().entries.map((entry) {
        return _buildAnimatedContainer(
          index: entry.key + 1,
          show: true,
          child: _buildDayContainer(
            day: entry.value['day'],
            timeRange: entry.value['timeRange'],
            backgroundColor: entry.value['backgroundColor'] ?? Colors.white,
            textColor: entry.value['textColor'] ?? const Color(0xFF000000),
          ),
        );
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final thisWeekData = [
      {'day': 'Monday', 'timeRange': 'Set 22:00 / Off 07:00'},
      {'day': 'Tuesday', 'timeRange': 'Set 23:00 / Off 07:00'},
      {'day': 'Wednesday', 'timeRange': 'Set 21:30 / Off 07:00'},
      {'day': 'Thursday', 'timeRange': 'Set 00:00 / Off 07:00'},
      {
        'day': 'Friday',
        'timeRange': 'Set 22:00 / Off 07:00',
        'backgroundColor': Theme.of(context).primaryColor,
        'textColor': Colors.white
      },
      {'day': 'Saturday', 'timeRange': 'Upcoming day'},
      {'day': 'Sunday', 'timeRange': 'Upcoming day'},
    ];

    final lastWeekData = [
      {'day': 'Monday', 'timeRange': 'Set 23:30 / Off 07:00'},
      {'day': 'Tuesday', 'timeRange': 'Set 20:00 / Off 06:00'},
      {'day': 'Wednesday', 'timeRange': 'Set 22:00 / Off 07:00'},
      {'day': 'Thursday', 'timeRange': 'Set 22:00 / Off 07:00'},
      {'day': 'Friday', 'timeRange': 'Set 00:00 / Off 07:00'},
      {'day': 'Saturday', 'timeRange': 'Set 22:00 / Off 07:00'},
      {'day': 'Sunday', 'timeRange': 'Set 00:00 / Off 05:00'},
    ];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF15161E)),
            onPressed: () => Get.back(),
          ),
          title: Text(
            'Sleep History',
            style: GoogleFonts.outfit(
              color: const Color(0xFF15161E),
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text('This Week'),
                      ),
                    ),
                    Tab(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text('Last Week'),
                      ),
                    ),
                  ],
                  labelStyle: GoogleFonts.figtree(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: GoogleFonts.figtree(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF606A85),
                  indicator: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // This Week Tab
                    ListView(
                      key: _listKeys[0],
                      children: _buildWeekItems('42,18', thisWeekData),
                    ),
                    // Last Week Tab
                    ListView(
                      key: _listKeys[1],
                      children: _buildWeekItems('57,15', lastWeekData),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}