import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';

/// Stimmwahl ExpansionTile
class VoiceSelectionExpansionTile extends StatelessWidget {
  final Widget voiceSelectWidget;
  final VoidCallback? onAddAudio;
  final Widget? audioFilesList;
  final Widget? voiceParamsWidget;
  final bool hasVoiceId;

  const VoiceSelectionExpansionTile({
    super.key,
    required this.voiceSelectWidget,
    this.onAddAudio,
    this.audioFilesList,
    this.voiceParamsWidget,
    required this.hasVoiceId,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.white24,
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.magenta, // GMBC Arrow
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
        backgroundColor: Colors.black.withValues(alpha: 0.95),
        collapsedIconColor: AppColors.magenta, // GMBC Arrow collapsed
        iconColor: AppColors.lightBlue, // GMBC Arrow expanded
        title: Text(
          context.read<LocalizationService>().t('voiceSelection'),
          style: const TextStyle(color: Colors.white),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ElevenLabs Voice Auswahl
                voiceSelectWidget,
                const SizedBox(height: 12),
                if (onAddAudio != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onAddAudio,
                      style: ElevatedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.magenta, AppColors.lightBlue],
                        ).createShader(bounds),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.read<LocalizationService>().t(
                                'avatars.details.audioUploadTitle',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.read<LocalizationService>().t(
                                'avatars.details.audioUploadSubtitle',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w300,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (onAddAudio != null) const SizedBox(height: 12),
                if (audioFilesList != null) audioFilesList!,
                const SizedBox(height: 12),
                // Stimmeinstellungen (nur anzeigen, wenn ein Klon/Voice-ID vorhanden ist)
                if (hasVoiceId && voiceParamsWidget != null) voiceParamsWidget!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
