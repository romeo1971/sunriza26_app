import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CustomPriceField - Preis-Feld für Input UND Anzeige
///
/// WICHTIG: Einheitliche Font-Parameter um Springen zu vermeiden:
/// - fontSize: 16
/// - fontWeight: FontWeight.w500
/// - height: 1.0
/// - letterSpacing: 0
///
/// Input: Max 2 Dezimalstellen (z.B. 12,34)
///
/// Diese Regel gilt für ALLE Input/Display Widgets (TextField, TextArea, Dropdown)!
class CustomPriceField extends StatefulWidget {
  final String? displayText;
  final String? hintText;
  final TextEditingController? controller;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;
  final bool isEditing;
  final bool autofocus;

  const CustomPriceField({
    super.key,
    this.displayText,
    this.hintText,
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.isEditing = false,
    this.autofocus = false,
  });

  @override
  State<CustomPriceField> createState() => _CustomPriceFieldState();
}

class _CustomPriceFieldState extends State<CustomPriceField> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // (alt) _formatInput entfernt – Logik steckt nun komplett im _priceInputFormatter

  /// Echtzeit-Formatter: nur Ziffern, ein Dezimaltrennzeichen, max. 2 Nachkommastellen
  static final TextInputFormatter
  _priceInputFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;

    // Nur erlaubte Zeichen behalten
    text = text.replaceAll(RegExp(r'[^0-9\.,]'), '');
    // Punkt zu Komma
    text = text.replaceAll('.', ',');
    // Nur ein Komma
    final parts = text.split(',');
    if (parts.length > 2) {
      text = '${parts[0]},${parts.sublist(1).join('')}';
    }
    // Max 2 Dezimalstellen
    final p2 = text.split(',');
    if (p2.length == 2 && p2[1].length > 2) {
      text = '${p2[0]},${p2[1].substring(0, 2)}';
    }

    // Wenn sich der Text durch den Formatter NICHT ändert, Auswahl beibehalten
    if (text == newValue.text) {
      return newValue;
    }

    // Cursor-Position möglichst beibehalten (kein Sprung ans Ende)
    final desiredOffset = newValue.selection.end;
    final clampedOffset = desiredOffset > text.length
        ? text.length
        : (desiredOffset < 0 ? 0 : desiredOffset);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: clampedOffset),
      composing: TextRange.empty,
    );
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.0,
      letterSpacing: 0,
    );

    // KEINE width - immer auto (IntrinsicWidth)
    return IntrinsicWidth(
      child: Container(
        alignment: Alignment.centerLeft,
        child: widget.isEditing
            ? TextField(
                controller: widget.controller,
                autofocus: widget.autofocus,
                keyboardType: widget.keyboardType,
                inputFormatters: [_priceInputFormatter],
                textAlign: TextAlign.left,
                cursorColor: Colors.white,
                style: textStyle,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(color: Colors.white, fontSize: 15),
                  fillColor: Colors.transparent,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: widget.onChanged,
              )
            : Text(widget.displayText ?? '', style: textStyle),
      ),
    );
  }
}
