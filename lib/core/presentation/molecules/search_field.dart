import 'package:flutter/material.dart';

/// Input de búsqueda con lupa y, opcionalmente, botón de limpiar.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.controller,
    this.hint = 'Buscar...',
    this.onChanged,
    this.onClear,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: onClear != null
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Limpiar',
                onPressed: onClear,
              )
            : null,
      ),
    );
  }
}
