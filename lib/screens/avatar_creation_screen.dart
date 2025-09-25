import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/avatar_service.dart';
import '../services/localization_service.dart';

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
        TextFormField(
          controller: _firstNameController,
          decoration: InputDecoration(
            labelText: context.read<LocalizationService>().t(
              'avatars.details.firstNameLabel',
            ),
            border: const OutlineInputBorder(),
          ),
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
        TextFormField(
          controller: _nicknameController,
          decoration: InputDecoration(
            labelText: context.read<LocalizationService>().t(
              'avatars.details.nicknameLabel',
            ),
            border: const OutlineInputBorder(),
            hintText: context.read<LocalizationService>().t(
              'avatars.details.nicknameHint',
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastNameController,
          decoration: InputDecoration(
            labelText: context.read<LocalizationService>().t(
              'avatars.details.lastNameLabel',
            ),
            border: const OutlineInputBorder(),
          ),
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
        TextFormField(
          controller: _birthDateController,
          decoration: InputDecoration(
            labelText: context.read<LocalizationService>().t(
              'avatars.details.birthDateLabel',
            ),
            hintText: context.read<LocalizationService>().t(
              'avatars.details.birthDateHint',
            ),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          readOnly: true,
          onTap: () => _selectDate(context, true),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _deathDateController,
          decoration: InputDecoration(
            labelText: context.read<LocalizationService>().t(
              'avatars.details.deathDateLabel',
            ),
            hintText: context.read<LocalizationService>().t(
              'avatars.details.deathDateHint',
            ),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          readOnly: true,
          onTap: () => _selectDate(context, false),
        ),
      ],
    );
  }

  Future<void> _selectDate(BuildContext context, bool isBirthDate) async {
    final loc = context.read<LocalizationService>();
    final String cancel = loc.t('avatars.details.cancel');
    final String ok = loc.t('avatars.details.ok');
    final String help = loc.t(
      isBirthDate
          ? 'avatars.details.birthDateHint'
          : 'avatars.details.deathDateHint',
    );
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isBirthDate
          ? DateTime.now().subtract(const Duration(days: 365 * 30))
          : DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      cancelText: cancel,
      confirmText: ok,
      helpText: help,
    );
    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _birthDate = picked;
          _birthDateController.text =
              '${picked.day}.${picked.month}.${picked.year}';
        } else {
          _deathDate = picked;
          _deathDateController.text =
              '${picked.day}.${picked.month}.${picked.year}';
        }
      });
    }
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
