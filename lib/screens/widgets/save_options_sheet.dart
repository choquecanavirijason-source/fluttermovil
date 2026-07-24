import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

/// Bottom sheet de opciones para guardar el diseño actual (hoy solo tiene la
/// opción "Lista de clientes"; el layout ya soporta agregar más filas).
class SaveOptionsSheet extends StatelessWidget {
  final VoidCallback onListaTap;

  const SaveOptionsSheet({super.key, required this.onListaTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Guardar diseño',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _OptionTile(
            icon: Icons.people_outline,
            label: 'Lista de clientes',
            onTap: onListaTap,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.actionGreen.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.actionGreen.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.actionGreen, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.actionGreen,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
