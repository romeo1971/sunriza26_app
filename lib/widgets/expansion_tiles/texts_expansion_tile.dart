import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';
import '../custom_text_field.dart';

/// Texte & Freitext ExpansionTile
class TextsExpansionTile extends StatelessWidget {
  final VoidCallback onAddTexts;
  final TextEditingController textAreaController;
  final VoidCallback onChanged;
  final List<Widget> chunkingParams;
  final VoidCallback onSaveTexts;
  final bool showSaveButton;

  const TextsExpansionTile({
    super.key,
    required this.onAddTexts,
    required this.textAreaController,
    required this.onChanged,
    required this.chunkingParams,
    required this.onSaveTexts,
    required this.showSaveButton,
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.read<LocalizationService>().t('texts'),
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
                  onPressed: onSaveTexts,
                  icon: const Icon(Icons.save_outlined, size: 14),
                  label: const Text(
                    'Speichern',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onAddTexts,
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
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => Theme.of(context)
                          .extension<AppGradients>()!
                          .magentaBlue
                          .createShader(bounds),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.read<LocalizationService>().t(
                              'avatars.details.textUploadTitle',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.read<LocalizationService>().t(
                              'avatars.details.textUploadSubtitle',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w300,
                              fontSize: 13,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                CustomTextArea(
                  label: context.read<LocalizationService>().t(
                    'avatars.details.freeTextLabel',
                  ),
                  controller: textAreaController,
                  hintText: context.read<LocalizationService>().t(
                    'avatars.details.freeTextHint',
                  ),
                  minLines: 4,
                  maxLines: 8,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 12),
                // Chunking Parameter
                ...chunkingParams,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
