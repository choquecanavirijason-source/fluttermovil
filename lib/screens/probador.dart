import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
class ProbadorScreen extends StatefulWidget {
  const ProbadorScreen({super.key});

  @override
  State<ProbadorScreen> createState() => _ProbadorScreenState();
}

class _ProbadorScreenState extends State<ProbadorScreen> {
  late Timer _timer;
  int _secondsRemaining = 5;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4A517);
    return Scaffold(
      backgroundColor: const Color(0xFF094732),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
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
            const SizedBox(height: 28),
            const Text(
              "Probador",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Estamos escaneando el modelo\nde tus ojos…",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(gold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
