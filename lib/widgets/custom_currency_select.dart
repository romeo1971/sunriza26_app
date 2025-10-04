import 'package:flutter/material.dart';

/// CustomCurrencySelect - Mini Dropdown für Währungsauswahl
class CustomCurrencySelect extends StatelessWidget {
  final String value;
  final void Function(String?) onChanged;

  const CustomCurrencySelect({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 28,
      child: Align(
        alignment: Alignment.center,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value.isEmpty ? '€' : value,
            items: const [
              DropdownMenuItem(value: '€', child: Text('€')),
              DropdownMenuItem(value: '\$', child: Text('\$')),
            ],
            onChanged: onChanged,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.normal,
              height: 1.0,
              letterSpacing: 0,
            ),
            dropdownColor: const Color(0xFF2A2A2A),
            icon: const Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: Colors.white70,
            ),
            isDense: true,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
