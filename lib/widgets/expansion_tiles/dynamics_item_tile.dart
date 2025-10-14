import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'expansion_tile_base.dart';

/// Einzelne Dynamics Item ExpansionTile (Basic, Lachen, Herz, etc.)
class DynamicsItemTile extends StatelessWidget {
  final String dynamicsId;
  final String dynamicsName;
  final String? dynamicsIcon;
  final Map<String, dynamic> dynamicsData;
  final String? selectedVideoUrl;
  final bool isGenerating;
  final int timeRemaining;

  // Parameter
  final double drivingMultiplier;
  final double animationScale;
  final int sourceMaxDim;
  final bool flagNormalizeLip;
  final bool flagPasteback;

  // Callbacks
  final VoidCallback onResetDefaults;
  final ValueChanged<double> onDrivingMultiplierChanged;
  final ValueChanged<double> onAnimationScaleChanged;
  final ValueChanged<int> onSourceMaxDimChanged;
  final ValueChanged<bool> onFlagNormalizeLipChanged;
  final ValueChanged<bool> onFlagPastebackChanged;
  final VoidCallback onGenerate;
  final VoidCallback? onSelectVideo; // Video wählen
  final VoidCallback? onDeselectVideo; // Video abwählen
  final VoidCallback? onDelete; // Dynamics löschen (nur nicht-Basic)
  final Widget Function({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    String? recommendation,
  })
  buildSlider;

  const DynamicsItemTile({
    super.key,
    required this.dynamicsId,
    required this.dynamicsName,
    this.dynamicsIcon,
    required this.dynamicsData,
    this.selectedVideoUrl,
    required this.isGenerating,
    required this.timeRemaining,
    required this.drivingMultiplier,
    required this.animationScale,
    required this.sourceMaxDim,
    required this.flagNormalizeLip,
    required this.flagPasteback,
    required this.onResetDefaults,
    required this.onDrivingMultiplierChanged,
    required this.onAnimationScaleChanged,
    required this.onSourceMaxDimChanged,
    required this.onFlagNormalizeLipChanged,
    required this.onFlagPastebackChanged,
    required this.onGenerate,
    this.onSelectVideo,
    this.onDeselectVideo,
    this.onDelete,
    required this.buildSlider,
  });

  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '⏳ ${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = dynamicsData['status'] as String?;
    final hasVideo = selectedVideoUrl != null && selectedVideoUrl!.isNotEmpty;
    final isReady = status == 'ready';

    return BaseExpansionTile(
      title: dynamicsName,
      emoji: dynamicsIcon ?? '🎭',
      initiallyExpanded: dynamicsId == 'basic',
      children: [
        // Status Badge
        if (status != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isReady
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isReady
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.orange.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isReady ? Icons.check_circle : Icons.pending,
                  color: isReady ? Colors.green : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isReady ? 'Bereit' : 'Nicht generiert',
                  style: TextStyle(
                    color: isReady ? Colors.green : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Video-Auswahl
        Text(
          'Driving Video:',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        if (hasVideo)
          // Video Preview + Deselect
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.lightBlue.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Video Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 60,
                    height: 60,
                    color: Colors.black,
                    child: const Icon(
                      Icons.play_circle,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Hero-Video',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                if (onDeselectVideo != null)
                  IconButton(
                    onPressed: onDeselectVideo,
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    tooltip: 'Video abwählen',
                  ),
              ],
            ),
          )
        else
          // Kein Video gewählt
          OutlinedButton.icon(
            onPressed: onSelectVideo,
            icon: const Icon(Icons.video_library, size: 18),
            label: const Text('Video wählen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),

        const SizedBox(height: 16),

        // Parameter Header + Default Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Parameter:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: onResetDefaults,
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Standard', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Sliders
        buildSlider(
          label: 'Expression Strength (Intensität)',
          value: drivingMultiplier,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          onChanged: onDrivingMultiplierChanged,
          valueLabel: drivingMultiplier.toStringAsFixed(2),
          recommendation: '💡 Empfohlen: 0.40-0.42 (natürlich)',
        ),
        const SizedBox(height: 12),

        buildSlider(
          label: 'Animation Scale (Region)',
          value: animationScale,
          min: 1.0,
          max: 2.5,
          divisions: 30,
          onChanged: onAnimationScaleChanged,
          valueLabel: animationScale.toStringAsFixed(2),
          recommendation: '💡 Empfohlen: 1.7 (Gesicht + Hals + Schultern)',
        ),
        const SizedBox(height: 12),

        buildSlider(
          label: 'Max Dimension (Auflösung)',
          value: sourceMaxDim.toDouble(),
          min: 512,
          max: 2048,
          divisions: 15,
          onChanged: (v) => onSourceMaxDimChanged(v.round()),
          valueLabel: '$sourceMaxDim px',
          recommendation: '💡 Empfohlen: 2048 (maximale Qualität)',
        ),
        const SizedBox(height: 16),

        // Toggle-Optionen
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Erweiterte Optionen:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text(
                  'Neutralisiere Lächeln',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  'Schließt Mund im Source-Bild vor Animation',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
                value: flagNormalizeLip,
                activeThumbColor: AppColors.lightBlue,
                onChanged: onFlagNormalizeLipChanged,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),

              SwitchListTile(
                title: const Text(
                  'Körper behalten (Pasteback)',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  '✅ WICHTIG: Behält vollen Körper + Original-Qualität!',
                  style: TextStyle(
                    color: Colors.green.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                value: flagPasteback,
                activeThumbColor: AppColors.lightBlue,
                onChanged: onFlagPastebackChanged,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Generieren Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (!hasVideo || isGenerating) ? null : onGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isGenerating
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.magenta),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatCountdown(timeRemaining),
                        style: const TextStyle(
                          color: AppColors.magenta,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  )
                : ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => Theme.of(context)
                        .extension<AppGradients>()!
                        .magentaBlue
                        .createShader(bounds),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Generieren',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // Löschen Button (nur nicht-Basic)
        if (dynamicsId != 'basic' && onDelete != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Dynamics löschen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
