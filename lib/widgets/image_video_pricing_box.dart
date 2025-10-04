import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'custom_currency_select.dart';

/// Image/Video Pricing Box (für Popup)
/// Zeigt Preis, Kostenpflichtig/Kostenlos Toggle, Credits, Edit-Stift
class ImageVideoPricingBox extends StatelessWidget {
  /// Price Input Formatter: Nur Zahlen, Komma, Punkt, max 2 Dezimalstellen
  static final TextInputFormatter _priceInputFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
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

        // Cursor-Position beibehalten
        if (text == newValue.text) {
          return newValue;
        }

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

  final bool isFree;
  final double effectivePrice;
  final String symbol;
  final int credits;
  final bool hasIndividualPrice;
  final bool showCredits;
  final VoidCallback onToggleFree;
  final VoidCallback onEdit;

  // Edit-Mode Props
  final bool isEditing;
  final TextEditingController? priceController;
  final String? tempCurrency;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final void Function(String?)? onCurrencyChanged;
  final VoidCallback? onGlobal;
  final bool showGlobalButton;

  const ImageVideoPricingBox({
    super.key,
    required this.isFree,
    required this.effectivePrice,
    required this.symbol,
    required this.credits,
    required this.hasIndividualPrice,
    required this.showCredits,
    required this.onToggleFree,
    required this.onEdit,
    this.isEditing = false,
    this.priceController,
    this.tempCurrency,
    this.onCancel,
    this.onSave,
    this.onCurrencyChanged,
    this.onGlobal,
    this.showGlobalButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // EDIT-MODE
    if (isEditing && priceController != null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFFE91E63), // Magenta
              AppColors.lightBlue, // Blue
              Color(0xFF00E5FF), // Cyan
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive Breakpoints
            final needsButtonWrap = constraints.maxWidth < 340;
            final needsGlobalWrap = constraints.maxWidth < 460;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zeile 1: Input + Currency (+ ggf. Global + X + Hook)
                Row(
                  children: [
                    // Input Field (auto width, NO border)
                    IntrinsicWidth(
                      child: TextField(
                        controller: priceController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        inputFormatters: [_priceInputFormatter],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Currency Select (auto width)
                    if (onCurrencyChanged != null)
                      SizedBox(
                        height: 40,
                        child: CustomCurrencySelect(
                          value: tempCurrency ?? '\$',
                          onChanged: onCurrencyChanged!,
                        ),
                      ),
                    // Global (wenn genug Platz + Button aktiv)
                    if (!needsGlobalWrap && showGlobalButton) ...[
                      const SizedBox(width: 8),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onGlobal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            height: 40,
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Global',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!needsButtonWrap) ...[
                      const Spacer(),
                      // X-Button (float right, links neben Hook)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onCancel,
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Hook-Button (Speichern)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onSave,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                            ),
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFFE91E63),
                                  Color(0xFFE91E63),
                                  AppColors.lightBlue,
                                  Color(0xFF00E5FF),
                                ],
                                stops: [0.0, 0.4, 0.7, 1.0],
                              ).createShader(bounds),
                              child: const Icon(
                                Icons.check,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Zeile 2: X (50%) + Hook (50%) wenn zu schmal
                if (needsButtonWrap) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // X-Button (50% width)
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: onCancel,
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.close,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Hook-Button (50% width)
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: onSave,
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                              ),
                              child: ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFFE91E63),
                                        Color(0xFFE91E63),
                                        AppColors.lightBlue,
                                        Color(0xFF00E5FF),
                                      ],
                                      stops: [0.0, 0.4, 0.7, 1.0],
                                    ).createShader(bounds),
                                child: const Icon(
                                  Icons.check,
                                  size: 24,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Zeile 3: Global (wenn zu schmal + sichtbar)
                if (needsButtonWrap && needsGlobalWrap && showGlobalButton) ...[
                  const SizedBox(height: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onGlobal,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh,
                              size: 16,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Global',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
    }

    // STANDARD-MODE
    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoint: Wenn zu schmal → 2 Zeilen
        final needsTwoLines = constraints.maxWidth < 280;

        if (needsTwoLines) {
          // 2-ZEILEN LAYOUT
          return Container(
            decoration: const BoxDecoration(color: Color(0x20FFFFFF)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ZEILE 1: Preis, Credits, Edit
                Row(
                  children: [
                    // Preis
                    Text(
                      '$symbol${effectivePrice.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Credits + Edit (nur wenn NICHT kostenlos)
                    if (!isFree) ...[
                      if (showCredits) ...[
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                          ).createShader(bounds),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$credits',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.diamond,
                                size: 12,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onEdit,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Colors.white70,
                              ),
                              if (hasIndividualPrice)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFFE91E63),
                                          AppColors.lightBlue,
                                          Color(0xFF00E5FF),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // ZEILE 2: Kostenpflichtig/Kostenlos (zentriert)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onToggleFree,
                    child: Center(
                      child: isFree
                          ? const Text(
                              'Kostenlos',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFFE91E63),
                                  AppColors.lightBlue,
                                  Color(0xFF00E5FF),
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'Kostenpflichtig',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // 1-ZEILEN LAYOUT (wie vorher)
        return Container(
          height: 40,
          decoration: const BoxDecoration(color: Color(0x20FFFFFF)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // LINKS: Preis
              Text(
                '$symbol${effectivePrice.toStringAsFixed(2).replaceAll('.', ',')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // MITTE: Kostenpflichtig/Kostenlos Toggle
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onToggleFree,
                  child: isFree
                      ? const Text(
                          'Kostenlos',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'Kostenpflichtig',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),
              const Spacer(),
              // RECHTS: Credits (GMBC) + Edit-Stift (nur wenn NICHT kostenlos)
              if (!isFree) ...[
                if (showCredits) ...[
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFFE91E63),
                        AppColors.lightBlue,
                        Color(0xFF00E5FF),
                      ],
                    ).createShader(bounds),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$credits',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.diamond,
                          size: 12,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onEdit,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: Colors.white70,
                        ),
                        if (hasIndividualPrice)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFE91E63),
                                    AppColors.lightBlue,
                                    Color(0xFF00E5FF),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
