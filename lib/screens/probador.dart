import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:test_face/eye_tracking_page.dart';

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
            Navigator.push(context, MaterialPageRoute(builder: (context) => EyeTrackingPage()));
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
    return Scaffold(
      backgroundColor: const Color(0xFF0C4B36),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ícono de espejo/cámara
            Image.asset(
              "assets/espejo.png",
              width: 100,
              height: 100,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.camera_front,
                  size: 100,
                  color: Colors.white,
                );
              },
            ),

            const SizedBox(height: 40),

            const Column(
              children: [
                Text(
                  "Preparando cámara...",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 10), // separación
                Text(
                  "Abriendo cámara en breve...",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color.fromARGB(0, 255, 255, 255), width: 4),
              ),
              child: Center(
                child: Opacity(
                  opacity: 0,
                  child: Text(
                    '$_secondsRemaining',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
