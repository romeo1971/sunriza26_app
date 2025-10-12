import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

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
    final gradients = Theme.of(context).extension<AppGradients>()!;
    final TextStyle effectiveStyle =
        style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.normal,
          letterSpacing: 0,
          height: 1.0,
        );

    return _CustomTextFieldWithGradient(
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
      effectiveStyle: effectiveStyle,
      enabled: enabled,
      focusNode: focusNode,
      onTap: onTap,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      hasValue: hasValue,
      label: label,
      hintText: hintText,
      contentPadding: contentPadding,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixIconConstraints,
      gradients: gradients,
    );
  }
}

class _CustomTextFieldWithGradient extends StatefulWidget {
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
  final TextStyle effectiveStyle;
  final bool enabled;
  final FocusNode? focusNode;
  final void Function()? onTap;
  final void Function(String)? onSubmitted;
  final TextInputAction? textInputAction;
  final bool hasValue;
  final String label;
  final String? hintText;
  final EdgeInsetsGeometry? contentPadding;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final BoxConstraints? prefixIconConstraints;
  final AppGradients gradients;

  const _CustomTextFieldWithGradient({
    required this.controller,
    required this.validator,
    required this.onChanged,
    required this.keyboardType,
    required this.readOnly,
    required this.maxLines,
    required this.minLines,
    required this.maxLength,
    required this.inputFormatters,
    required this.textCapitalization,
    required this.obscureText,
    required this.effectiveStyle,
    required this.enabled,
    required this.focusNode,
    required this.onTap,
    required this.onSubmitted,
    required this.textInputAction,
    required this.hasValue,
    required this.label,
    required this.hintText,
    required this.contentPadding,
    required this.suffixIcon,
    required this.prefixIcon,
    required this.prefixIconConstraints,
    required this.gradients,
  });

  @override
  State<_CustomTextFieldWithGradient> createState() =>
      _CustomTextFieldWithGradientState();
}

class _CustomTextFieldWithGradientState
    extends State<_CustomTextFieldWithGradient> {
  late FocusNode _internalFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    } else {
      _internalFocusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _internalFocusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      readOnly: widget.readOnly,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      obscureText: widget.obscureText,
      style: widget.effectiveStyle,
      cursorColor: AppColors.magenta,
      enabled: widget.enabled,
      focusNode: _internalFocusNode,
      onTap: widget.onTap,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: widget.effectiveStyle.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.normal,
          backgroundColor: const Color(0xFF0A0A0A),
        ),
        floatingLabelStyle: widget.effectiveStyle.copyWith(
          color: _isFocused ? Colors.white : Colors.white70,
          fontWeight: FontWeight.normal,
          backgroundColor: const Color(0xFF0A0A0A),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: widget.hintText,
        hintStyle: widget.effectiveStyle.copyWith(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF0A0A0A),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
          gapPadding: 12,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Color(0xFFFF2EC8), // GMBC Magenta
            width: 2,
          ),
          gapPadding: 12,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
          gapPadding: 8,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
          gapPadding: 8,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12, width: 1),
        ),
        contentPadding:
            widget.contentPadding ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: widget.suffixIcon,
        prefixIcon: widget.prefixIcon,
        prefixIconConstraints: widget.prefixIconConstraints,
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
