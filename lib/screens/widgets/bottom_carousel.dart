import 'dart:ui';

import 'package:flutter/material.dart';

class BottomCarousel extends StatelessWidget {
  final int selectedLash;
  final ValueChanged<int> onSelect;
  final List<String> imagePaths;

  const BottomCarousel({
    super.key,
    required this.selectedLash,
    required this.onSelect,
    required this.imagePaths,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 15),
        child: Container(
          width: double.infinity,
          height: 100,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: imagePaths.length,
            itemBuilder: (context, index) {
              final isSelected = selectedLash == index;
              return GestureDetector(
                onTap: () => onSelect(index),
                child: AnimatedScale(
                  scale: isSelected ? 1.18 : 0.92,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(isSelected ? 0.95 : 0.45),
                      border: isSelected
                          ? Border.all(
                              color: Colors.white.withOpacity(0.95),
                              width: 2,
                            )
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.13),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.asset(
                          imagePaths[index],
                          fit: BoxFit.contain,
                          semanticLabel: 'Lash style ${index + 1}',
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
