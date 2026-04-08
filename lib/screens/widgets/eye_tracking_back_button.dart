import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:test_face/screens/Home.dart';

class EyeTrackingBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const EyeTrackingBackButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 35,
      left: 12,
      child: GestureDetector(
        onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const HomePage()),
  );
},
        child: ClipRRect(
          borderRadius: BorderRadius.circular(80),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
