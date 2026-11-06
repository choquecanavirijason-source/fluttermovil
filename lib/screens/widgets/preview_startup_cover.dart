import 'package:flutter/material.dart';
import 'lash_loading_eye.dart';

/// Covers startup work until an actual camera analysis frame is available.
/// No timer reveals the preview; the timer in the page only reports failure.
class PreviewStartupCover extends StatelessWidget {
  const PreviewStartupCover({
    super.key,
    required this.ready,
    required this.onBack,
    this.error,
  });
  final bool ready;
  final String? error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      ignoring: ready,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: ready
            ? const SizedBox.shrink(key: ValueKey('preview-ready'))
            : Material(
                key: ValueKey(
                  error == null ? 'preview-loading' : 'preview-error',
                ),
                color: const Color(0xFF094732),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -.25),
                      radius: 1.15,
                      colors: [
                        Color(0xFF1B4B3B),
                        Color(0xFF0C2B24),
                        Color(0xFF061B17),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          left: 8,
                          child: IconButton(
                            tooltip: 'Volver',
                            onPressed: onBack,
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (error == null) ...[
                                  const Text(
                                    'EL ARTE DE TU MIRADA',
                                    style: TextStyle(
                                      color: Color(0xFFB9C8BA),
                                      fontSize: 10,
                                      letterSpacing: 3.2,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  const LashLoadingEye(),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Una mirada única.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'serif',
                                      color: Color(0xFFF2E7D0),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: -.5,
                                    ),
                                  ),
                                ],
                                if (error != null)
                                  const Icon(
                                    Icons.videocam_off_outlined,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                const SizedBox(height: 20),
                                Text(
                                  error ?? 'Preparando el probador…',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    letterSpacing: .5,
                                  ),
                                ),
                                if (error == null) ...[
                                  const SizedBox(height: 26),
                                  const SizedBox(
                                    width: 36,
                                    child: Divider(
                                      color: Color(0xFF8B805E),
                                      thickness: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'PROBADOR VIRTUAL',
                                    style: TextStyle(
                                      color: Color(0xFF829D8C),
                                      fontSize: 9,
                                      letterSpacing: 2.6,
                                    ),
                                  ),
                                ],
                                if (error != null)
                                  TextButton(
                                    onPressed: onBack,
                                    child: const Text(
                                      'Volver',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
