import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnalogClock extends StatefulWidget {
  final double size;
  final Color backgroundColor;
  final Color numberColor;
  final Color handColor;
  final Color secondHandColor;

  const AnalogClock({
    Key? key,
    this.size = 300,
    this.backgroundColor = Colors.white,
    this.numberColor = Colors.black,
    this.handColor = Colors.black,
    this.secondHandColor = Colors.red,
  }) : super(key: key);

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock> {
  Timer? _timer;
  late DateTime _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _ClockPainter(
          currentTime: _currentTime,
          backgroundColor: widget.backgroundColor,
          numberColor: widget.numberColor,
          handColor: widget.handColor,
          secondHandColor: widget.secondHandColor,
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  final DateTime currentTime;
  final Color backgroundColor;
  final Color numberColor;
  final Color handColor;
  final Color secondHandColor;

  _ClockPainter({
    required this.currentTime,
    required this.backgroundColor,
    required this.numberColor,
    required this.handColor,
    required this.secondHandColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    // Draw clock face
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, backgroundPaint);
    canvas.drawCircle(center, radius, borderPaint);

    // Draw numbers
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 1; i <= 12; i++) {
      final angle = -pi / 2 + (i * pi / 6);
      final numberRadius = radius - 30;
      final x = center.dx + numberRadius * cos(angle);
      final y = center.dy + numberRadius * sin(angle);

      textPainter.text = TextSpan(
        text: i.toString(),
        style: GoogleFonts.rozhaOne(
          color: numberColor,
          fontSize: radius * 0.2,

        ),
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Hour hand
    final hour = currentTime.hour % 12;
    final hourAngle = pi / 6 * hour + pi / 360 * currentTime.minute - pi / 2;
    _drawHand(canvas, center, hourAngle, radius * 0.4, radius * 0.015, handColor);

    // Minute hand
    final minuteAngle = pi / 30 * currentTime.minute - pi / 2;
    _drawHand(canvas, center, minuteAngle, radius * 0.6, radius * 0.01, handColor);

    // Second hand
    final secondAngle = pi / 30 * currentTime.second - pi / 2;
    _drawHand(canvas, center, secondAngle, radius * 0.7, radius * 0.005, secondHandColor);

    // Center dot
    canvas.drawCircle(
      center,
      radius * 0.03,
      Paint()..color = handColor,
    );
  }

  void _drawHand(Canvas canvas, Offset center, double angle, double length,
      double width, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + length * cos(angle),
        center.dy + length * sin(angle),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}