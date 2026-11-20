import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

class EyeTrackingFilterRow extends StatelessWidget {
  final int selectedFilter;
  final ValueChanged<int> onSelect;
  final bool embedded;
  final Widget? recommendation;

  const EyeTrackingFilterRow({
    super.key,
    required this.selectedFilter,
    required this.onSelect,
    this.embedded = false,
    this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chip('RECOMENDADOS', 0),
              const SizedBox(width: 8),
              _chip('TODOS', 1),
            ],
          ),
        ),
        ?recommendation,
      ],
    );
    if (embedded) return content;
    return Positioned(bottom: 150, left: 20, right: 0, child: content);
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
