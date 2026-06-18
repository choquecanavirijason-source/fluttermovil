import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Índice de la pestaña activa del shell.
final shellTabProvider = StateProvider<int>((ref) => 0);
