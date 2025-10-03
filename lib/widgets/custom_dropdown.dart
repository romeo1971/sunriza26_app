import 'package:flutter/material.dart';

/// CustomDropdown - Dropdown in einem Widget
///
/// WICHTIG: Einheitliche Font-Parameter um Springen zu vermeiden:
/// - fontSize: 16
/// - fontWeight: normal
/// - letterSpacing: 0
/// - height: 1.0
///
/// Diese Regel gilt für ALLE Input/Display Widgets!
class CustomDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;
  final String? hint;
  final bool enabled;

  const CustomDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.normal,
          fontSize: 16,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: false,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white30, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white30, width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: enabled ? onChanged : null,
          isExpanded: true,
          dropdownColor: Colors.black87,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.normal,
            letterSpacing: 0,
            height: 1.0,
          ),
          hint: hint != null
              ? Text(hint!, style: const TextStyle(color: Colors.white54))
              : null,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
        ),
      ),
    );
  }
}
