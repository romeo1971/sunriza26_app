import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';

/// Personendaten ExpansionTile
class PersonDataExpansionTile extends StatelessWidget {
  final Widget inputFieldsWidget;
  final VoidCallback? onSavePersonData;
  final bool showSaveButton;

  const PersonDataExpansionTile({
    super.key,
    required this.inputFieldsWidget,
    this.onSavePersonData,
    this.showSaveButton = false,
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
          children: [
            Expanded(
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.personDataTitle',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (showSaveButton && onSavePersonData != null)
              TextButton.icon(
                onPressed: onSavePersonData,
                icon: const Icon(Icons.save, size: 16, color: AppColors.lightBlue),
                label: const Text(
                  'Speichern',
                  style: TextStyle(color: AppColors.lightBlue, fontSize: 13),
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 1.0),
            child: inputFieldsWidget,
          ),
        ],
      ),
    );
  }
}
