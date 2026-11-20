import 'package:flutter/material.dart';
import 'design_thumbnail_image.dart';

import 'package:Probador/core/theme/app_colors.dart';

class EyeTrackingDesignMenuBar extends StatelessWidget {
  final List<String> designImages;
  final List<String> designOptions;
  final int selectedDesign;
  final ValueChanged<int>? onSelectDesign;
  final VoidCallback onOpenGrid;
  final String categoryTitle;
  final String? helperText;
  final String resetLabel;
  final VoidCallback? onReset;
  final Widget? filters;

  const EyeTrackingDesignMenuBar({
    super.key,
    required this.designImages,
    required this.designOptions,
    required this.selectedDesign,
    this.onSelectDesign,
    required this.onOpenGrid,
    required this.categoryTitle,
    this.helperText,
    this.resetLabel = 'Restaurar original',
    this.onReset,
    this.filters,
  });

  static const _green = AppColors.actionGreen;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 10,
      right: 10,
      bottom: 62,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera compacta: categoría · estado · restablecer ──
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Text(
                    categoryTitle,
                    style: const TextStyle(
                      color: Color(0xFFF3E6C8),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (helperText != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          helperText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (onReset != null)
                    Tooltip(
                      message: resetLabel,
                      child: InkWell(
                        onTap: onReset,
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.restart_alt_rounded,
                            color: Color(0xFFD8C79E),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (filters != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: filters,
              ),
            // ── Opciones ─────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(designOptions.length, (index) {
                          final isSelected = index == selectedDesign;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => onSelectDesign?.call(index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 66,
                                height: 62,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(11),
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
                                    DesignThumbnailImage(
                                      path: designImages[index],
                                      size: 28,
                                      color: isSelected ? _green : Colors.white,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      designOptions[index],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isSelected
                                            ? _green
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 9.5,
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
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onOpenGrid,
                    child: Container(
                      width: 30,
                      height: 62,
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
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
