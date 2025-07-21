import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import '../../../controllers/alarm/alarm_controller.dart';
import '../../../controllers/stats/stats_controller.dart';
import '../../../core/shared_preferences/sleep_history_prefs.dart';
import '../../../core/database/database_helper.dart';

class SleepHistoryWidget extends StatefulWidget {
  const SleepHistoryWidget({super.key});

  @override
  SleepHistoryWidgetState createState() => SleepHistoryWidgetState();
}

class SleepHistoryWidgetState extends State<SleepHistoryWidget>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animationController;
  final List<GlobalKey<AnimatedListState>> _listKeys = [
    GlobalKey<AnimatedListState>(),
    GlobalKey<AnimatedListState>(),
  ];

  final SleepStatisticsController _controller =
      Get.put(SleepStatisticsController());

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
      _controller.loadSleepStatistics();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when screen is focused
    _controller.loadSleepStatistics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Show confirmation dialog for deleting all sleep history
  Future<void> _showDeleteConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning,
                color: Colors.red,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              SizedBox(width: 8),
              Text(
                'Delete All Sleep History',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: MediaQuery.of(context).size.width * 0.04,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete ALL sleep history data? This action cannot be undone.',
            style: GoogleFonts.inter(
              fontSize: MediaQuery.of(context).size.width * 0.035,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteAllSleepHistory();
              },
              child: Text(
                'Delete All',
                style: GoogleFonts.inter(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Delete all sleep history data
  Future<void> _deleteAllSleepHistory() async {
    try {
      // Show loading dialog
      Get.dialog(
        Center(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Deleting sleep history...',
                  style: GoogleFonts.inter(),
                ),
              ],
            ),
          ),
        ),
        barrierDismissible: false,
      );

      // Delete all sleep history from both SharedPreferences and Database
      await SleepHistoryPrefs.clearAllSleepHistory();
      
      // Also clear from database
      final dbHelper = DatabaseHelper();
      await dbHelper.clearAllSleepHistory();
      
      // Close loading dialog
      Get.back();
      
      // Refresh the controller
      await _controller.loadSleepStatistics();
      
      // Show success message
      Get.snackbar(
        '✅ Sleep History Deleted',
        'All sleep history data has been successfully deleted.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        duration: const Duration(seconds: 3),
        icon: Icon(
          Icons.check_circle,
          color: Colors.green,
        ),
      );
      
    } catch (e) {
      // Close loading dialog
      Get.back();
      
      // Show error message
      Get.snackbar(
        '❌ Delete Failed',
        'Failed to delete sleep history. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        duration: const Duration(seconds: 3),
        icon: Icon(
          Icons.error,
          color: Colors.red,
        ),
      );
      
      print('Error deleting sleep history: $e');
    }
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
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: 6,
      ),
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
                    fontSize: MediaQuery.of(context).size.width * 0.025,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Text(
                  timeRange,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.interTight(
                    fontSize: MediaQuery.of(context).size.width * 0.035,
                    color: textColor,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: FaIcon(
                  FontAwesomeIcons.bed,
                  color: Colors.black,
                  size: MediaQuery.of(context).size.width * 0.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalHoursCard(String hours) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: 8,
      ),
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
          color: Colors.black,
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
                'Total hours slept this week',
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontSize: MediaQuery.of(context).size.width * 0.03,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  textScaleFactor: MediaQuery.of(context).textScaleFactor,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: hours,
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF15161E),
                          fontSize: MediaQuery.of(context).size.width * 0.1,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      TextSpan(
                        text: ' Hours/Min',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF606A85),
                          fontSize: MediaQuery.of(context).size.width * 0.035,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildWeekItems(
      String hours, List<Map<String, dynamic>> dayData) {
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
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final isPad = MediaQuery.of(context).size.width >= 768;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.05, 1.0],
            colors: [
              Color(0xFFAF5B73), // Blue for top 10%
              Color(0xFFF5F5F5), // Light blue transition
              Color(0xFFF5F5F5), // Light grey for the rest
            ],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: const Color(0xFF15161E),
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              onPressed: () => Get.back(),
            ),
            title: Text(
              'Sleep History',
              style: GoogleFonts.outfit(
                color: const Color(0xFF15161E),
                fontSize: isPad
                    ? 28
                    : isTablet
                    ? 26
                    : 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: const Color(0xFF15161E),
                  size: MediaQuery.of(context).size.width * 0.06,
                ),
                onPressed: () => _controller.refreshSleepStatistics(),
                tooltip: 'Refresh Data',
              ),
              IconButton(
                icon: Icon(
                  Icons.cleaning_services,
                  color: Colors.orange,
                  size: MediaQuery.of(context).size.width * 0.06,
                ),
                onPressed: () => _showClearCorruptedDataDialog(),
                tooltip: 'Clear Corrupted Data',
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_forever,
                  color: Colors.red,
                  size: MediaQuery.of(context).size.width * 0.06,
                ),
                onPressed: () => _showDeleteConfirmationDialog(),
                tooltip: 'Delete All Sleep History',
              ),
            ],
            elevation: 0,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  margin: EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: MediaQuery.of(context).size.width * 0.04,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 24 : 16,
                            vertical: 10,
                          ),
                          child: Text(
                            'This Week',
                            style: TextStyle(
                              fontSize:
                              MediaQuery.of(context).size.width * 0.035,
                            ),
                          ),
                        ),
                      ),
                      Tab(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 24 : 16,
                            vertical: 10,
                          ),
                          child: Text(
                            'Last Week',
                            style: TextStyle(
                              fontSize:
                              MediaQuery.of(context).size.width * 0.035,
                            ),
                          ),
                        ),
                      ),
                    ],
                    labelStyle: GoogleFonts.figtree(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: GoogleFonts.figtree(
                      fontSize: isTablet ? 18 : 16,
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
                  child: GetX<SleepStatisticsController>(
                    builder: (controller) {
                      if (isTablet) {
                        return TabBarView(
                          controller: _tabController,
                          children: [
                            CustomScrollView(
                              key: _listKeys[0],
                              slivers: [
                                SliverToBoxAdapter(
                                  child: _buildAnimatedContainer(
                                    index: 0,
                                    show: true,
                                    child: _buildTotalHoursCard(
                                        controller.thisWeekTotalHours.value),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.all(8.0),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: isPad ? 3 : 2,
                                      childAspectRatio: 2.5,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                        final data =
                                        controller.thisWeekSleepData[index];
                                        return _buildAnimatedContainer(
                                          index: index + 1,
                                          show: true,
                                          child: _buildDayContainer(
                                            day: data['day'],
                                            timeRange: data['timeRange'],
                                            backgroundColor:
                                            data['backgroundColor'] ??
                                                Colors.white,
                                            textColor: data['textColor'] ??
                                                const Color(0xFF000000),
                                          ),
                                        );
                                          },
                                      childCount:
                                      controller.thisWeekSleepData.length,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            CustomScrollView(
                              key: _listKeys[1],
                              slivers: [
                                SliverToBoxAdapter(
                                  child: _buildAnimatedContainer(
                                    index: 0,
                                    show: true,
                                    child: _buildTotalHoursCard(
                                        controller.lastWeekTotalHours.value),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.all(8.0),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: isPad ? 3 : 2,
                                      childAspectRatio: 2.5,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                        final data =
                                        controller.lastWeekSleepData[index];
                                        return _buildAnimatedContainer(
                                          index: index + 1,
                                          show: true,
                                          child: _buildDayContainer(
                                            day: data['day'],
                                            timeRange: data['timeRange'],
                                            backgroundColor:
                                            data['backgroundColor'] ??
                                                Colors.white,
                                            textColor: data['textColor'] ??
                                                const Color(0xFF000000),
                                          ),
                                        );
                                      },
                                      childCount:
                                      controller.lastWeekSleepData.length,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          ListView(
                            key: _listKeys[0],
                            children: _buildWeekItems(
                              controller.thisWeekTotalHours.value,
                              controller.thisWeekSleepData,
                            ),
                          ),
                          ListView(
                            key: _listKeys[1],
                            children: _buildWeekItems(
                              controller.lastWeekTotalHours.value,
                              controller.lastWeekSleepData,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Clear corrupted sleep history data
  Future<void> _clearCorruptedData() async {
    try {
      // Show loading dialog
      Get.dialog(
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Clearing corrupted data...',
                  style: GoogleFonts.inter(),
                ),
              ],
            ),
          ),
        ),
        barrierDismissible: false,
      );

      // Get the alarm controller to access the clear method
      final alarmController = Get.find<AlarmController>();
      await alarmController.clearCorruptedSleepHistory();
      
      // Close loading dialog
      Get.back();
      
      // Refresh the controller
      await _controller.loadSleepStatistics();
      
      // Show success message
      Get.snackbar(
        '🧹 Corrupted Data Cleared',
        'All corrupted sleep history data has been cleared. You can now set new alarms.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.blue[100],
        duration: const Duration(seconds: 3),
        icon: Icon(
          Icons.cleaning_services,
          color: Colors.blue,
        ),
      );
      
    } catch (e) {
      // Close loading dialog
      Get.back();
      
      // Show error message
      Get.snackbar(
        '❌ Clear Failed',
        'Failed to clear corrupted data. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        duration: const Duration(seconds: 3),
        icon: Icon(
          Icons.error,
          color: Colors.red,
        ),
      );
      
      print('Error clearing corrupted data: $e');
    }
  }

  /// Show confirmation dialog for clearing corrupted data
  Future<void> _showClearCorruptedDataDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.cleaning_services,
                color: Colors.orange,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              SizedBox(width: 8),
              Text(
                'Clear Corrupted Data',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: MediaQuery.of(context).size.width * 0.04,
                ),
              ),
            ],
          ),
          content: Text(
            'This will clear all corrupted sleep history data and fix the 0:00 hours issue. Your valid sleep data will be preserved.',
            style: GoogleFonts.inter(
              fontSize: MediaQuery.of(context).size.width * 0.035,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _clearCorruptedData();
              },
              child: Text(
                'Clear Corrupted',
                style: GoogleFonts.inter(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
