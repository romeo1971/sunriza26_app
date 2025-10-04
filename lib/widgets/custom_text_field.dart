import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CustomTextField - Input UND Display in einem Widget
///
/// WICHTIG: Einheitliche Font-Parameter um Springen zu vermeiden:
/// - fontSize: 16
/// - fontWeight: normal
/// - cursorColor: Colors.white
/// - letterSpacing: 0
/// - height: 1.0
///
/// Diese Regel gilt für ALLE Input/Display Widgets!
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
  final BoxConstraints? prefixIconConstraints;
  final String? hintText;
  final TextStyle? style;
  final EdgeInsetsGeometry? contentPadding;
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
    this.prefixIconConstraints,
    this.hintText,
    this.style,
    this.contentPadding,
    this.enabled = true,
    this.focusNode,
    this.onTap,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = controller?.text.trim().isNotEmpty ?? false;
    final TextStyle effectiveStyle =
        style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.normal,
          letterSpacing: 0,
          height: 1.0,
        );

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
      style: effectiveStyle,
      cursorColor: Colors.white,
      enabled: enabled,
      focusNode: focusNode,
      onTap: onTap,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: hasValue ? label : null,
        labelStyle: effectiveStyle.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.normal,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        hintText: hintText ?? label,
        hintStyle: effectiveStyle.copyWith(color: Colors.white54),
        filled: false,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white30, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white30, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12, width: 1),
        ),
        contentPadding:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
        prefixIconConstraints: prefixIconConstraints,
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
