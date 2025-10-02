import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CustomTextField mit integriertem Label (platzsparendes Design)
///
/// Features:
/// - Label wird innerhalb des Input-Feldes angezeigt
/// - Grüner Border wenn Wert vorhanden, grau wenn leer
/// - Unterstützt alle Standard TextField-Parameter
/// - Konsistentes Design-Pattern für die gesamte App
class CustomTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? hintText;
  final TextStyle? style;
  final bool enabled;
  final FocusNode? focusNode;
  final void Function()? onTap;
  final void Function(String)? onSubmitted;
  final TextInputAction? textInputAction;

  const CustomTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.onChanged,
    this.keyboardType,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.hintText,
    this.style,
    this.enabled = true,
    this.focusNode,
    this.onTap,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = controller?.text.trim().isNotEmpty ?? false;

    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      keyboardType: keyboardType,
      readOnly: readOnly,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      style: style ?? const TextStyle(color: Colors.white),
      enabled: enabled,
      focusNode: focusNode,
      onTap: onTap,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: hasValue ? label : null,
        labelStyle: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.normal,
          fontSize: 16,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        hintText: hintText ?? label,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: false,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white30, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white30, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
        counterStyle: const TextStyle(color: Colors.white54),
      ),
    );
  }
}

/// CustomTextArea für mehrzeilige Texteingaben
///
/// Features:
/// - Mindestens 3 Zeilen hoch
/// - Expandiert automatisch mit Inhalt
/// - Gleicher Stil wie CustomTextField
class CustomTextArea extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final String? hintText;
  final bool enabled;
  final TextCapitalization textCapitalization;

  const CustomTextArea({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.onChanged,
    this.minLines = 3,
    this.maxLines = 8,
    this.maxLength,
    this.hintText,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.sentences,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTextField(
      label: label,
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      hintText: hintText,
      enabled: enabled,
      textCapitalization: textCapitalization,
      keyboardType: TextInputType.multiline,
    );
  }
}
