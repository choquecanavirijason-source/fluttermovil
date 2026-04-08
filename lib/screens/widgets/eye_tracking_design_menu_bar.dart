import 'package:flutter/material.dart';

class EyeTrackingDesignMenuBar extends StatelessWidget {
  final List<String> designImages;
  final List<String> designOptions;
  final int selectedDesign;
  final ValueChanged<int>? onSelectDesign;
  final VoidCallback onOpenGrid;

  const EyeTrackingDesignMenuBar({
    super.key,
    required this.designImages,
    required this.designOptions,
    required this.selectedDesign,
    this.onSelectDesign,
    required this.onOpenGrid,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Container(
        padding: const EdgeInsets.only(top: 12, bottom: 10, left: 8, right: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(designOptions.length, (index) {
                    final isSelected = index == selectedDesign;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GestureDetector(
                        onTap: () => onSelectDesign?.call(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.black,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                designImages[index],
                                width: 38,
                                height: 38,
                                color: isSelected ? null : Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.white54,
                                  size: 38,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                designOptions[index],
                                style: TextStyle(
                                  color:
                                      isSelected ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            GestureDetector(
              onTap: onOpenGrid,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.grid_view, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
