import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Audio Pricing Box (Standard-Ansicht)
/// Zeigt Preis, Kostenpflichtig/Kostenlos Toggle, Credits, Edit-Stift
class AudioPricingBox extends StatelessWidget {
  final bool isFree;
  final double effectivePrice;
  final String symbol;
  final int credits;
  final bool hasIndividualPrice;
  final bool showCredits; // Wenn globalPrice enabled oder individual price gesetzt
  final VoidCallback onToggleFree;
  final VoidCallback onEdit;

  const AudioPricingBox({
    super.key,
    required this.isFree,
    required this.effectivePrice,
    required this.symbol,
    required this.credits,
    required this.hasIndividualPrice,
    required this.showCredits,
    required this.onToggleFree,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0x20FFFFFF), // Leichter transparenter Hintergrund
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        children: [
          // MITTE (absolut zentriert): "Kostenpflichtig" / "Kostenlos" Toggle
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onToggleFree,
                child: Center(
                  child: isFree
                      ? const Text(
                          'Kostenlos',
                          style: TextStyle(
                            color: Colors.white54, // lightgrey
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFFE91E63), // Magenta
                              AppColors.lightBlue, // Blue
                              Color(0xFF00E5FF), // Cyan
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'Kostenpflichtig',
                            style: TextStyle(
                              color: Colors.white, // GMBC-Farbe
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // LINKS: Preis-Anzeige (über Toggle-Layer)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$symbol${effectivePrice.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          // RECHTS: Credits (GMBC) + Edit-Stift (nur wenn NICHT kostenlos)
          if (!isFree)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Credits mit GMBC-Farbe und Diamant
                  if (showCredits) ...[
                    IgnorePointer(
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Color(0xFFE91E63), // Magenta
                            AppColors.lightBlue, // Blue
                            Color(0xFF00E5FF), // Cyan
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
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Edit-Stift mit optionalem farbigem Punkt (individueller Preis)
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
                          // Farbiger Punkt (GMBC) oben rechts, wenn individueller Preis
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
                                      Color(0xFFE91E63), // Magenta
                                      AppColors.lightBlue, // Blue
                                      Color(0xFF00E5FF), // Cyan
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
              ),
            ),
        ],
      ),
    );
  }
}

