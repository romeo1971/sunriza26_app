import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// CustomDateField für Datumseingaben mit integriertem Label
///
/// Features:
/// - Label wird innerhalb des Feldes angezeigt
/// - GMBC Gradient Icon wenn Datum ausgewählt, grau wenn leer
/// - Öffnet DatePicker beim Tap
/// - Clear-Button (X) um Datum zu löschen
/// - Konsistentes Design mit CustomTextField
class CustomDateField extends StatelessWidget {
  final String label;
  final DateTime? selectedDate;
  final void Function(DateTime?) onDateSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? Function(DateTime?)? validator;
  final bool enabled;
  final String dateFormat;
  final bool allowClear;

  const CustomDateField({
    super.key,
    required this.label,
    required this.selectedDate,
    required this.onDateSelected,
    this.firstDate,
    this.lastDate,
    this.validator,
    this.enabled = true,
    this.dateFormat = 'dd.MM.yyyy',
    this.allowClear = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedDate != null;
    final displayText = hasValue
        ? DateFormat(dateFormat).format(selectedDate!)
        : '';

    return InkWell(
      onTap: enabled ? () => _pickDate(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
          suffixIcon: hasValue && allowClear
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFE91E63), // Magenta
                          AppColors.lightBlue,
                          Color(0xFF00E5FF), // Cyan
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.calendar_today,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: enabled ? () => onDateSelected(null) : null,
                      child: const Icon(
                        Icons.clear,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                )
              : hasValue
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFE91E63), // Magenta
                      AppColors.lightBlue,
                      Color(0xFF00E5FF), // Cyan
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.white,
                    size: 20,
                  ),
                )
              : const Icon(
                  Icons.calendar_today,
                  color: Colors.white54,
                  size: 20,
                ),
        ),
        child: Text(
          displayText.isEmpty ? label : displayText,
          style: TextStyle(
            color: displayText.isEmpty ? Colors.white54 : Colors.white,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? now,
      firstDate: firstDate ?? DateTime(1900),
      lastDate: lastDate ?? DateTime(2100),
      locale: const Locale('de', 'DE'),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.magenta, // GMBC
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF1E1E1E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onDateSelected(picked);
    }
  }
}
