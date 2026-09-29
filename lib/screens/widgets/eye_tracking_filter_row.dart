import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

class EyeTrackingFilterRow extends StatelessWidget {
  final int selectedFilter;
  final ValueChanged<int> onSelect;

  const EyeTrackingFilterRow({
    super.key,
    required this.selectedFilter,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 150,
      left: 20,
      right: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip('COMPATIBLE', 0),
            const SizedBox(width: 8),
            _chip('EXPLORAR', 1),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, int index) {
    final isSelected = selectedFilter == index;
    return GestureDetector(
      onTap: () => onSelect(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 290),
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? AppColors.actionGreen : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
