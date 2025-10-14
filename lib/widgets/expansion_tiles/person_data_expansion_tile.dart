import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';

/// Personendaten ExpansionTile
class PersonDataExpansionTile extends StatelessWidget {
  final Widget inputFieldsWidget;

  const PersonDataExpansionTile({super.key, required this.inputFieldsWidget});

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
          context.read<LocalizationService>().t(
            'avatars.details.personDataTitle',
          ),
          style: const TextStyle(color: Colors.white),
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
