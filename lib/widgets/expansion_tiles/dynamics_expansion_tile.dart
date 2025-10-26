import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'expansion_tile_base.dart';
import 'dynamics_item_tile.dart';
import 'live_avatar_tile.dart';

/// Dynamics Container ExpansionTile - zeigt alle Dynamics als separate Tiles
class DynamicsExpansionTile extends StatelessWidget {
  // Hero Video State
  final String? heroVideoUrl;
  final bool heroVideoTooLong;
  final double heroVideoDuration;

  // Live Avatar State
  final String? heroImageUrl;
  final String? heroAudioUrl;
  final VoidCallback? onGenerateLiveAvatar;
  final bool isGeneratingLiveAvatar;
  final String? liveAvatarAgentId;

  // Dynamics State
  final Map<String, Map<String, dynamic>> dynamicsData;

  // Parameter State (pro Dynamics)
  final Map<String, double> drivingMultipliers;
  final Map<String, double> animationScales;
  final Map<String, int> sourceMaxDims;
  final Map<String, bool> flagsNormalizeLip;
  final Map<String, bool> flagsPasteback;

  // Generation State
  final Set<String> generatingDynamics;
  final Map<String, int> dynamicsTimeRemaining;

  // Callbacks
  final VoidCallback onShowVideoTrimDialog;
  final VoidCallback onSwitchToVideos;
  final Function(String dynamicsId) onResetDefaults;
  final Function(String dynamicsId, double value) onDrivingMultiplierChanged;
  final Function(String dynamicsId, double value) onAnimationScaleChanged;
  // onSourceMaxDimChanged entfernt - Wert wird automatisch berechnet
  final Function(String dynamicsId, bool value) onFlagNormalizeLipChanged;
  final Function(String dynamicsId, bool value) onFlagPastebackChanged;
  final Function(String dynamicsId) onGenerate;
  final Function(String dynamicsId) onCancelGeneration;
  final Function(String dynamicsId)? onSelectVideo;
  final Function(String dynamicsId)? onDeselectVideo;
  final Function(String dynamicsId)? onDeleteDynamics;
  final VoidCallback onShowCreateDynamicsDialog;
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
  final bool dynamicsEnabled;
  final bool lipsyncEnabled;
  final ValueChanged<bool> onToggleDynamics;
  final ValueChanged<bool> onToggleLipsync;

  const DynamicsExpansionTile({
    super.key,
    required this.heroVideoUrl,
    required this.heroVideoTooLong,
    required this.heroVideoDuration,
    this.heroImageUrl,
    this.heroAudioUrl,
    this.onGenerateLiveAvatar,
    this.isGeneratingLiveAvatar = false,
    this.liveAvatarAgentId,
    required this.dynamicsData,
    required this.drivingMultipliers,
    required this.animationScales,
    required this.sourceMaxDims,
    required this.flagsNormalizeLip,
    required this.flagsPasteback,
    required this.generatingDynamics,
    required this.dynamicsTimeRemaining,
    required this.onShowVideoTrimDialog,
    required this.onSwitchToVideos,
    required this.onResetDefaults,
    required this.onDrivingMultiplierChanged,
    required this.onAnimationScaleChanged,
    // onSourceMaxDimChanged entfernt
    required this.onFlagNormalizeLipChanged,
    required this.onFlagPastebackChanged,
    required this.onGenerate,
    required this.onCancelGeneration,
    this.onSelectVideo,
    this.onDeselectVideo,
    this.onDeleteDynamics,
    required this.onShowCreateDynamicsDialog,
    required this.buildSlider,
    required this.dynamicsEnabled,
    required this.lipsyncEnabled,
    required this.onToggleDynamics,
    required this.onToggleLipsync,
  });

  @override
  Widget build(BuildContext context) {
    final hasHeroVideo = heroVideoUrl != null && heroVideoUrl!.isNotEmpty;

    // Wenn Video global deaktiviert ist: nur Header mit Toggle anzeigen
    if (!dynamicsEnabled) {
      return BaseExpansionTile(
        title: 'Dynamics   ',
        emoji: '',
        initiallyExpanded: false,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Basic',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onToggleDynamics(!dynamicsEnabled),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Video inaktiv',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 48,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    return BaseExpansionTile(
      title: 'Dynamics   ',
      emoji: '', // Kein Icon
      initiallyExpanded: false,
      children: [
        // Header-Leiste: Tabs + Video On/Off rechts
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Basic',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  // const SizedBox(width: 8),
                ],
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onToggleDynamics(!dynamicsEnabled),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Video ${dynamicsEnabled ? 'aktiv' : 'inaktiv'}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 48,
                          height: 28,
                          decoration: BoxDecoration(
                            color: dynamicsEnabled
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: dynamicsEnabled
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                gradient: dynamicsEnabled
                                    ? const LinearGradient(
                                        colors: [
                                          AppColors.magenta,
                                          AppColors.lightBlue,
                                        ],
                                      )
                                    : null,
                                color: dynamicsEnabled
                                    ? null
                                    : Colors.white.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Manuelles Reload (falls Listener verpasst):
        // Hinweis: "Neu laden" Button wird weiter unten im DynamicsItemTile-Kontext angezeigt,
        // damit er näher an den Controls ist.
        // const SizedBox(height: 4),
        // Info Text: Kein Hero-Video
        if (!hasHeroVideo)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bitte Hero-Video hochladen, um Dynamics zu generieren',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        // Warnung: Hero-Video zu lang
        if (hasHeroVideo && heroVideoTooLong)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ Hero-Video ist ${heroVideoDuration.toStringAsFixed(1)}s lang!\n'
                        'Für Dynamics MAX 10 Sekunden erlaubt.',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onShowVideoTrimDialog,
                        icon: const Icon(Icons.content_cut, size: 18),
                        label: const Text('Video trimmen (0-10s)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSwitchToVideos,
                        icon: const Icon(Icons.video_library, size: 18),
                        label: const Text('Anderes Video'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        if (hasHeroVideo) ...[
          const SizedBox(height: 16),

          // Render jede Dynamics als eigene Tile (Basic ohne Header)
          ...dynamicsData.entries.map((entry) {
            final id = entry.key;
            final data = entry.value;
            // Name aus Daten oder ID mit Großbuchstaben am Anfang
            String name = (data['name'] as String?) ?? id;
            if (name == 'basic') name = 'Basic'; // Großschreibung
            final icon = (data['icon'] as String?);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DynamicsItemTile(
                dynamicsId: id,
                dynamicsName: name,
                dynamicsIcon: icon,
                dynamicsData: data,
                selectedVideoUrl: hasHeroVideo ? heroVideoUrl : null,
                heroVideoTooLong: heroVideoTooLong,
                isGenerating: generatingDynamics.contains(id),
                timeRemaining: dynamicsTimeRemaining[id] ?? 0,
                drivingMultiplier: drivingMultipliers[id] ?? 0.41,
                animationScale: animationScales[id] ?? 1.7,
                sourceMaxDim: sourceMaxDims[id] ?? 2048,
                flagNormalizeLip: flagsNormalizeLip[id] ?? true,
                flagPasteback: flagsPasteback[id] ?? true,
                onResetDefaults: () => onResetDefaults(id),
                onDrivingMultiplierChanged: (v) =>
                    onDrivingMultiplierChanged(id, v),
                onAnimationScaleChanged: (v) => onAnimationScaleChanged(id, v),
                // onSourceMaxDimChanged entfernt
                onFlagNormalizeLipChanged: (v) =>
                    onFlagNormalizeLipChanged(id, v),
                onFlagPastebackChanged: (v) => onFlagPastebackChanged(id, v),
                onGenerate: () {
                  if (hasHeroVideo && !heroVideoTooLong) onGenerate(id);
                },
                onCancelGeneration: () => onCancelGeneration(id),
                onSelectVideo: onSelectVideo != null
                    ? () => onSelectVideo!(id)
                    : null,
                onDeselectVideo: onDeselectVideo != null
                    ? () => onDeselectVideo!(id)
                    : null,
                onDelete: onDeleteDynamics != null
                    ? () => onDeleteDynamics!(id)
                    : null,
                buildSlider: buildSlider,
                dynamicsEnabled: dynamicsEnabled,
                lipsyncEnabled: lipsyncEnabled,
                onToggleDynamics: onToggleDynamics,
                onToggleLipsync: onToggleLipsync,
                showHeader: id != 'basic',
              ),
            );
          }),

          // Live Avatar Tile (unter Basic)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LiveAvatarTile(
              heroImageUrl: heroImageUrl,
              heroAudioUrl: heroAudioUrl,
              onGenerate: onGenerateLiveAvatar,
              isGenerating: isGeneratingLiveAvatar,
              agentId: liveAvatarAgentId,
            ),
          ),

          // const SizedBox(height: 16),

          // + Neue Dynamics Button - OBSOLETE (auskommentiert)
          // if (dynamicsData['basic']?['status'] == 'ready')
          //   SizedBox(
          //     width: double.infinity,
          //     child: OutlinedButton(
          //       onPressed: onShowCreateDynamicsDialog,
          //       style: OutlinedButton.styleFrom(
          //         padding: const EdgeInsets.symmetric(vertical: 14),
          //         side: BorderSide(
          //           color: AppColors.magenta.withValues(alpha: 0.5),
          //         ),
          //         shape: RoundedRectangleBorder(
          //           borderRadius: BorderRadius.circular(12),
          //         ),
          //       ),
          //       child: Row(
          //         mainAxisAlignment: MainAxisAlignment.center,
          //         children: [
          //           const Icon(Icons.add, color: AppColors.magenta, size: 20),
          //           const SizedBox(width: 8),
          //           Text(
          //             'Neue Dynamics anlegen',
          //             style: TextStyle(
          //               color: Colors.white.withValues(alpha: 0.9),
          //               fontWeight: FontWeight.w500,
          //             ),
          //           ),
          //         ],
          //       ),
          //     ),
          //   ),
        ],
        // Footer entfernt – globale Toggles werden in DynamicsItemTile angezeigt
      ],
    );
  }
}
