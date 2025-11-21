import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';
import '../custom_text_field.dart';

/// Begrüßungstext ExpansionTile
class GreetingTextExpansionTile extends StatelessWidget {
  final TextEditingController greetingController;
  final String? currentVoiceId;
  final bool isTestingVoice;
  final VoidCallback onTestVoice;
  final VoidCallback onSaveGreeting;
  final bool showSaveButton;
  final VoidCallback onChanged;
  final Widget roleDropdown;

  const GreetingTextExpansionTile({
    super.key,
    required this.greetingController,
    this.currentVoiceId,
    required this.isTestingVoice,
    required this.onTestVoice,
    required this.onSaveGreeting,
    required this.showSaveButton,
    required this.onChanged,
    required this.roleDropdown,
  });

  @override
  Widget build(BuildContext context) {
    final hasVoice = currentVoiceId?.trim().isNotEmpty ?? false;

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.read<LocalizationService>().t('greetingText'),
              style: const TextStyle(color: Colors.white),
            ),
            if (showSaveButton)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onSaveGreeting,
                  icon: const Icon(Icons.save_outlined, size: 14),
                  label: const Text(
                    'Speichern',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            if (hasVoice)
              IconButton(
                icon: const Icon(
                  Icons.volume_up,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: context.read<LocalizationService>().t(
                  'avatars.details.voiceTestTooltip',
                ),
                onPressed: isTestingVoice ? null : onTestVoice,
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTextArea(
                  label: context.read<LocalizationService>().t(
                    'avatars.details.greetingLabel',
                  ),
                  controller: greetingController,
                  hintText: context.read<LocalizationService>().t(
                    'avatars.details.greetingHint',
                  ),
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 16),
                roleDropdown,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
