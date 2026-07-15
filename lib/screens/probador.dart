import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
class ProbadorScreen extends StatefulWidget {
  const ProbadorScreen({super.key});

  @override
  State<ProbadorScreen> createState() => _ProbadorScreenState();
}

class _ProbadorScreenState extends State<ProbadorScreen>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _secondsRemaining = 5;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsRemaining--;
      });

      // Cuando llegue a 0, navega a la cámara
      if (_secondsRemaining == 4) {
        _timer.cancel();
        // Espera un poco y luego navega
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            context.pushReplacement('/camera');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF094732),
      body: Center(
        child: ScaleTransition(
          scale: _pulseAnimation,
          child: Image.asset(
            "assets/espejo.png",
            width: 130,
            height: 130,
            color: Colors.white,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.remove_red_eye_outlined,
              size: 130,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
