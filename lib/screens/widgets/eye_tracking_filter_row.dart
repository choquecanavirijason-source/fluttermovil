import 'package:flutter/material.dart';

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
      bottom: 200,
      left: 0,
      right: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip('COMPATIBLE', 0),
            const SizedBox(width: 13),
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(isSelected ? 1 : 0.3),
            width: 1.1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? const Color(0xFF0D5C41) : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
