import 'package:flutter/material.dart';

class EyeTrackingDesignMenuBar extends StatelessWidget {
  final List<String> designImages;
  final List<String> designOptions;
  final int selectedDesign;
  final ValueChanged<int>? onSelectDesign;
  final VoidCallback onOpenGrid;
  final String categoryTitle;

  const EyeTrackingDesignMenuBar({
    super.key,
    required this.designImages,
    required this.designOptions,
    required this.selectedDesign,
    this.onSelectDesign,
    required this.onOpenGrid,
    required this.categoryTitle,
  });

  static const _green = Color(0xFF0D5C41);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 65,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Pestaña ──────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: const BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Text(
              categoryTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          // ── Panel de opciones ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: GestureDetector(
                            onTap: () => onSelectDesign?.call(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 60,
                              height: 60,
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.15),
                                  width: 1.1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    designImages[index],
                                    width: 34,
                                    height: 34,
                                    color: isSelected ? _green : Colors.white,
                                    errorBuilder: (_, __, _) => const Icon(
                                      Icons.image_not_supported,
                                      color: Colors.white54,
                                      size: 34,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    designOptions[index],
                                    style: TextStyle(
                                      color: isSelected ? _green : Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 9,
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
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onOpenGrid,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: const Icon(
                      Icons.grid_view,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
