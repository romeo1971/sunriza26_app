import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/avatar_service.dart';
import '../services/localization_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_date_field.dart';

class AvatarCreationScreen extends StatefulWidget {
  const AvatarCreationScreen({super.key});

  @override
  State<AvatarCreationScreen> createState() => _AvatarCreationScreenState();
}

class _AvatarCreationScreenState extends State<AvatarCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();

  final AvatarService _avatarService = AvatarService();
  DateTime? _birthDate;
  DateTime? _deathDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _nicknameController.dispose();
    _lastNameController.dispose();
    _birthDateController.dispose();
    _deathDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.read<LocalizationService>().t('avatars.createTooltip'),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_firstNameController.text.trim().isNotEmpty && !_isLoading)
            IconButton(
              tooltip: context.read<LocalizationService>().t(
                'avatars.details.saveTooltip',
              ),
              onPressed: _isLoading ? null : _createAvatar,
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBasicInfoSection(),
                    const SizedBox(height: 24),
                    _buildDateSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.read<LocalizationService>().t(
            'avatars.details.personDataTitle',
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          label: context.read<LocalizationService>().t(
            'avatars.details.firstNameLabel',
          ),
          controller: _firstNameController,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.read<LocalizationService>().t(
                'avatars.details.firstNameRequired',
              );
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        CustomTextField(
          label: context.read<LocalizationService>().t(
            'avatars.details.nicknameLabel',
          ),
          hintText: context.read<LocalizationService>().t(
            'avatars.details.nicknameHint',
          ),
          controller: _nicknameController,
        ),
        const SizedBox(height: 16),
        CustomTextField(
          label: context.read<LocalizationService>().t(
            'avatars.details.lastNameLabel',
          ),
          controller: _lastNameController,
        ),
      ],
    );
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.read<LocalizationService>().t(
            'avatars.details.personDataTitle',
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        CustomDateField(
          label: context.read<LocalizationService>().t(
            'avatars.details.birthDateLabel',
          ),
          selectedDate: _birthDate,
          onDateSelected: (date) {
            setState(() {
              _birthDate = date;
              if (date != null) {
                _birthDateController.text =
                    '${date.day}.${date.month}.${date.year}';
              }
            });
          },
        ),
        const SizedBox(height: 16),
        CustomDateField(
          label: context.read<LocalizationService>().t(
            'avatars.details.deathDateLabel',
          ),
          selectedDate: _deathDate,
          onDateSelected: (date) {
            setState(() {
              _deathDate = date;
              if (date != null) {
                _deathDateController.text =
                    '${date.day}.${date.month}.${date.year}';
              }
            });
          },
        ),
      ],
    );
  }

  Future<void> _createAvatar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final avatar = await _avatarService.createAvatar(
        firstName: _firstNameController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        lastName: _lastNameController.text.trim().isEmpty
            ? null
            : _lastNameController.text.trim(),
        birthDate: _birthDate,
        deathDate: _deathDate,
      );

      if (avatar != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dataSavedSuccessfully',
                ),
              ),
            ),
          );
          Navigator.pop(context, avatar);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.saveFailed',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = context.read<LocalizationService>().t(
          'avatars.details.errorGeneric',
          params: {'msg': e.toString()},
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Texte/Medien Helpers entfernt – nur Personendaten bleiben
}
