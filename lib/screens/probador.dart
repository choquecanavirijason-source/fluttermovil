import 'package:flutter/material.dart';
import '../eye_tracking_page.dart';

/// Shared entry for named routes and the service screen. Start the actual
/// preview immediately instead of delaying it behind a timed splash route.
class ProbadorScreen extends StatelessWidget {
  const ProbadorScreen({super.key});

  @override
  Widget build(BuildContext context) => const EyeTrackingPage();
}
