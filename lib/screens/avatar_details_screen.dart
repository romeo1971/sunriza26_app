import 'package:flutter/material.dart';
import '../models/avatar_data.dart';

class AvatarDetailsScreen extends StatefulWidget {
  const AvatarDetailsScreen({super.key});

  @override
  State<AvatarDetailsScreen> createState() => _AvatarDetailsScreenState();
}

class _AvatarDetailsScreenState extends State<AvatarDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();

  DateTime? _birthDate;
  DateTime? _deathDate;
  int? _calculatedAge;

  AvatarData? _avatarData;

  @override
  void initState() {
    super.initState();
    // Empfange AvatarData von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AvatarData) {
        setState(() {
          _avatarData = args;
          _firstNameController.text = args.firstName;
          _nicknameController.text = args.nickname ?? '';
          _lastNameController.text = args.lastName ?? '';
          _birthDate = args.birthDate;
          _deathDate = args.deathDate;
          _calculatedAge = args.calculatedAge;

          if (_birthDate != null) {
            _birthDateController.text = _formatDate(_birthDate!);
          }
          if (_deathDate != null) {
            _deathDateController.text = _formatDate(_deathDate!);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatar Details'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar-Bild oben
              _buildAvatarImage(),

              const SizedBox(height: 24),

              // Eingabefelder
              _buildInputFields(),

              const SizedBox(height: 32),

              // Speichern-Button
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage() {
    return Center(
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.deepPurple, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: _avatarData?.avatarImageUrl != null
            ? ClipOval(
                child: Image.network(
                  _avatarData!.avatarImageUrl!,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade100,
                    child: const Icon(
                      Icons.person,
                      size: 80,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              )
            : CircleAvatar(
                backgroundColor: Colors.deepPurple.shade100,
                child: const Icon(
                  Icons.person,
                  size: 80,
                  color: Colors.deepPurple,
                ),
              ),
      ),
    );
  }

  Widget _buildInputFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vorname (Pflichtfeld)
        _buildTextField(
          controller: _firstNameController,
          label: 'Vorname *',
          hint: 'Gib den Vornamen ein',
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Vorname ist erforderlich';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Spitzname (optional)
        _buildTextField(
          controller: _nicknameController,
          label: 'Spitzname',
          hint: 'Gib einen Spitznamen ein (optional)',
        ),

        const SizedBox(height: 16),

        // Nachname (optional)
        _buildTextField(
          controller: _lastNameController,
          label: 'Nachname',
          hint: 'Gib den Nachnamen ein (optional)',
        ),

        const SizedBox(height: 16),

        // Geburtsdatum (optional)
        _buildDateField(
          controller: _birthDateController,
          label: 'Geburtsdatum',
          hint: 'Wähle das Geburtsdatum',
          onTap: () => _selectBirthDate(),
        ),

        const SizedBox(height: 16),

        // Sterbedatum (optional)
        _buildDateField(
          controller: _deathDateController,
          label: 'Sterbedatum',
          hint: 'Wähle das Sterbedatum (optional)',
          onTap: () => _selectDeathDate(),
        ),

        const SizedBox(height: 16),

        // Berechnetes Alter anzeigen
        if (_calculatedAge != null) _buildAgeDisplay(),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.text.isEmpty ? hint : controller.text,
                    style: TextStyle(
                      color: controller.text.isEmpty
                          ? Colors.grey.shade500
                          : Colors.black,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today, color: Colors.deepPurple),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgeDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.cake, color: Colors.green.shade600),
          const SizedBox(width: 12),
          Text(
            'Berechnetes Alter: $_calculatedAge Jahre',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saveAvatarDetails,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Speichern',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = _formatDate(picked);
        _calculateAge();
      });
    }
  }

  Future<void> _selectDeathDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: _birthDate ?? DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _deathDate = picked;
        _deathDateController.text = _formatDate(picked);
        _calculateAge();
      });
    }
  }

  void _calculateAge() {
    if (_birthDate != null) {
      final endDate = _deathDate ?? DateTime.now();
      final age = endDate.year - _birthDate!.year;
      final monthDiff = endDate.month - _birthDate!.month;

      if (monthDiff < 0 || (monthDiff == 0 && endDate.day < _birthDate!.day)) {
        _calculatedAge = age - 1;
      } else {
        _calculatedAge = age;
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  void _saveAvatarDetails() {
    if (_formKey.currentState!.validate()) {
      // Update AvatarData with form data
      if (_avatarData != null) {
        final updatedAvatarData = _avatarData!.copyWith(
          firstName: _firstNameController.text.trim(),
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
          lastName: _lastNameController.text.trim().isEmpty
              ? null
              : _lastNameController.text.trim(),
          birthDate: _birthDate,
          deathDate: _deathDate,
          calculatedAge: _calculatedAge,
          updatedAt: DateTime.now(),
        );

        // TODO: Save to Firestore with Firebase Storage URLs
        _showSuccessSnackBar('Avatar-Details gespeichert!');

        // Navigate to Avatar Chat with updated data
        Navigator.pushNamed(
          context,
          '/avatar-chat',
          arguments: updatedAvatarData,
        );
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
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
}
